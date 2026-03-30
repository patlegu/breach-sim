"""
main.py — FastAPI backend pour la démo breach-sim.

Endpoints :
    GET  /api/health           → état de chargement des modèles
    GET  /api/scenario         → métadonnées du scénario
    POST /api/scenario/run     → lance le scénario
    POST /api/scenario/reset   → annule et remet à zéro
    GET  /api/scenario/stream  → SSE : tokens + événements

Démarrage :
    uvicorn demo.backend.main:app --port 8888 --workers 1
    # --workers 1 obligatoire : OnnxRunner est un singleton CPU
"""

import asyncio
import json
import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from fastapi.staticfiles import StaticFiles

from .onnx_runner import OnnxRunner
from .scenario import SCENARIO_STEPS

logging.basicConfig(level=logging.INFO, format="%(asctime)s — %(levelname)s — %(message)s")
logger = logging.getLogger(__name__)

ONNX_DIR = Path(os.getenv("ONNX_DIR", Path(__file__).resolve().parent.parent.parent / "cyber-agent-engine" / "onnx"))

runner = OnnxRunner()
_sse_queue: asyncio.Queue = asyncio.Queue()
_scenario_running = False
_stop_event = asyncio.Event()


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Chargement des modèles ONNX depuis %s...", ONNX_DIR)
    await runner.load_all(ONNX_DIR)
    yield
    runner._executor.shutdown(wait=False)


app = FastAPI(title="breach-sim", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://localhost:8888"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Helpers SSE ──────────────────────────────────────────────────────────────

async def _broadcast(event: dict) -> None:
    await _sse_queue.put(event)


def _sse_format(event: dict) -> str:
    return f"data: {json.dumps(event, ensure_ascii=False)}\n\n"


# ── Scénario ─────────────────────────────────────────────────────────────────

async def _run_scenario_task() -> None:
    global _scenario_running
    try:
        await _broadcast({"type": "scenario_start"})

        for step in SCENARIO_STEPS:
            if _stop_event.is_set():
                break

            await _broadcast({
                "type": "step_start",
                "step_id": step["id"],
                "agent": step["agent"],
                "title": step["title"],
                "description": step["description"],
                "cap": step["cap"],
            })

            tokens_buf = []

            def on_token(text: str, sid=step["id"]) -> None:
                tokens_buf.append(text)
                asyncio.ensure_future(_broadcast({"type": "token", "step_id": sid, "text": text}))

            full_text, latency = await runner.generate_streaming(
                agent=step["agent"],
                cap=step["cap"],
                on_token=on_token,
                stop_event=_stop_event,
            )

            if _stop_event.is_set():
                break

            # Parser le tool_call depuis la sortie
            tool_call = _parse_tool_call(full_text)

            await _broadcast({
                "type": "step_done",
                "step_id": step["id"],
                "tool_call": tool_call,
                "raw": full_text.strip(),
                "latency_s": round(latency, 2),
            })

            await _broadcast({
                "type": "topology_update",
                "event": step["topology_event"],
            })

        if not _stop_event.is_set():
            await _broadcast({"type": "scenario_done"})

    except Exception as e:
        logger.exception("Erreur scénario : %s", e)
        await _broadcast({"type": "scenario_error", "message": str(e)})
    finally:
        _scenario_running = False


def _parse_tool_call(text: str) -> dict | None:
    text = text.strip()
    for stop in ["<|im_end|>", "<|endoftext|>"]:
        text = text.replace(stop, "").strip()
    try:
        data = json.loads(text)
        if isinstance(data, list) and data:
            return data[0]
        if isinstance(data, dict):
            return data
    except json.JSONDecodeError:
        pass
    return {"raw": text}


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/api/health")
async def health():
    return {
        "ready": runner.ready,
        "loaded": runner._loaded,
        "pending": [a for a in ("opnsense", "wireguard", "crowdsec") if a not in runner._loaded],
    }


@app.get("/api/scenario")
async def get_scenario():
    return {
        "steps": [
            {
                "id": s["id"],
                "title": s["title"],
                "agent": s["agent"],
                "description": s["description"],
                "cap": s["cap"],
            }
            for s in SCENARIO_STEPS
        ]
    }


@app.post("/api/scenario/run")
async def run_scenario():
    global _scenario_running
    if not runner.ready:
        raise HTTPException(503, "Modèles ONNX pas encore chargés")
    if _scenario_running:
        raise HTTPException(409, "Scénario déjà en cours")
    _stop_event.clear()
    _scenario_running = True
    asyncio.create_task(_run_scenario_task())
    return {"status": "started"}


@app.post("/api/scenario/reset")
async def reset_scenario():
    global _scenario_running
    _stop_event.set()
    _scenario_running = False
    await _broadcast({"type": "scenario_reset"})
    return {"status": "reset"}


@app.get("/api/scenario/stream")
async def stream_events():
    async def event_generator():
        while True:
            try:
                event = await asyncio.wait_for(_sse_queue.get(), timeout=15.0)
                yield _sse_format(event)
            except asyncio.TimeoutError:
                yield _sse_format({"type": "ping"})

    return StreamingResponse(event_generator(), media_type="text/event-stream")


# ── Static files (frontend buildé) ───────────────────────────────────────────

_static_dir = Path(__file__).parent / "static"
if _static_dir.exists():
    app.mount("/", StaticFiles(directory=str(_static_dir), html=True), name="static")
