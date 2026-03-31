"""
onnx_runner.py — Inférence ONNX int4 CPU avec streaming token par token.

Les modèles sont chargés une seule fois au démarrage (lifespan FastAPI).
L'inférence tourne dans un ThreadPoolExecutor (generate_next_token est synchrone/bloquante).
"""

import asyncio
import json
import logging
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Callable

import numpy as np

logger = logging.getLogger(__name__)

SYSTEM_PROMPTS = {
    "opnsense": (
        "Tu es un agent OPNsense. Tu reçois des directives structurées du coordinateur "
        "sous forme de paquets JSON (format CAP v1) et tu génères des appels d'API précis "
        "sous forme de tool_calls. Tu ne réponds jamais en langage naturel — uniquement des tool_calls."
    ),
    "wireguard": (
        "Tu es un agent WireGuard. Tu reçois des directives structurées du coordinateur "
        "sous forme de paquets JSON (format CAP v1) et tu génères des appels d'API précis "
        "sous forme de tool_calls. Tu ne réponds jamais en langage naturel — uniquement des tool_calls."
    ),
    "crowdsec": (
        "Tu es un agent CrowdSec. Tu reçois des directives structurées du coordinateur "
        "sous forme de paquets JSON (format CAP v1) et tu génères des appels d'API précis "
        "sous forme de tool_calls. Tu ne réponds jamais en langage naturel — uniquement des tool_calls."
    ),
}


def build_prompt(agent: str, cap: dict) -> str:
    system = SYSTEM_PROMPTS[agent]
    user = json.dumps(cap, ensure_ascii=False)
    return (
        f"<|im_start|>system\n{system}<|im_end|>\n"
        f"<|im_start|>user\n{user}<|im_end|>\n"
        f"<|im_start|>assistant\n"
    )


class OnnxRunner:
    def __init__(self):
        self._models: dict = {}
        self._tokenizers: dict = {}
        self._executor = ThreadPoolExecutor(max_workers=1)
        self._loaded: list[str] = []
        self.ready = False

    async def load_all(self, onnx_dir: Path) -> None:
        try:
            import onnxruntime_genai as og
        except ImportError:
            raise RuntimeError("onnxruntime-genai non installé. pip install onnxruntime-genai")

        loop = asyncio.get_event_loop()
        for agent in ("opnsense", "wireguard", "crowdsec"):
            model_path = onnx_dir / agent
            if not model_path.exists():
                raise FileNotFoundError(f"Modèle ONNX introuvable : {model_path}")

            logger.info("Chargement %s...", agent)
            model = await loop.run_in_executor(
                self._executor,
                lambda p=str(model_path): og.Model(p)
            )
            self._models[agent] = model
            self._tokenizers[agent] = og.Tokenizer(model)
            self._loaded.append(agent)
            logger.info("%s chargé.", agent)

        self.ready = True
        logger.info("Tous les modèles ONNX sont prêts.")

    async def generate_streaming(
        self,
        agent: str,
        cap: dict,
        on_token: Callable[[str], None],
        stop_event: asyncio.Event,
        max_new_tokens: int = 256,
    ) -> tuple[str, float]:
        """
        Lance l'inférence dans le thread pool, appelle on_token pour chaque token.
        Retourne (full_text, latency_seconds).
        """
        import onnxruntime_genai as og

        loop = asyncio.get_event_loop()
        prompt = build_prompt(agent, cap)

        def _run():
            model = self._models[agent]
            tokenizer = self._tokenizers[agent]
            tokenizer_stream = tokenizer.create_stream()
            input_ids = np.array(tokenizer.encode(prompt), dtype=np.int32)

            params = og.GeneratorParams(model)
            params.set_search_options(
                max_length=len(input_ids) + max_new_tokens,
                temperature=0.1,
                top_p=0.95,
                do_sample=False,
            )

            t0 = time.perf_counter()
            output_tokens = []
            generator = og.Generator(model, params)
            generator.append_tokens(input_ids)

            while not generator.is_done():
                if stop_event.is_set():
                    break
                generator.generate_next_token()
                token = generator.get_next_tokens()[0]
                output_tokens.append(token)
                text = tokenizer_stream.decode(token)
                if "<|im_end|>" in text or "<|endoftext|>" in text:
                    break
                loop.call_soon_threadsafe(on_token, text)

            latency = time.perf_counter() - t0
            del generator
            return tokenizer.decode(output_tokens), latency

        return await loop.run_in_executor(self._executor, _run)
