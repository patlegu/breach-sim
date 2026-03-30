"""
main.py — FastAPI backend pour la démo breach-sim.

Endpoints :
    GET  /api/health              → état de chargement des modèles
    GET  /api/scenarios           → liste des scénarios disponibles
    GET  /api/scenarios/{id}      → détail d'un scénario (steps inclus)
    POST /api/scenario/run        → lance un scénario { "scenario_id": "..." }
    POST /api/scenario/reset      → annule et remet à zéro
    GET  /api/scenario/stream     → SSE : tokens + événements

Démarrage :
    uvicorn backend.main:app --port 8888 --workers 1
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
from pydantic import BaseModel

from .onnx_runner import OnnxRunner
from .scenario import SCENARIOS, SCENARIO_ORDER

logging.basicConfig(level=logging.INFO, format="%(asctime)s — %(levelname)s — %(message)s")
logger = logging.getLogger(__name__)

ONNX_DIR = Path(os.getenv("ONNX_DIR", Path(__file__).resolve().parent.parent / "onnx"))

runner = OnnxRunner()
_sse_queues: list[asyncio.Queue] = []
_scenario_running = False
_stop_event = asyncio.Event()
_current_scenario_id: str | None = None

_MODEL_INFO = {
    "opnsense":  {"name": "Qwen2.5-3B + OPNsense LoRA",  "precision": "int4", "repo": "patlegu/opnsense-qwen25-onnx-int4"},
    "wireguard": {"name": "Qwen2.5-3B + WireGuard LoRA", "precision": "int4", "repo": "patlegu/wireguard-qwen25-onnx-int4"},
    "crowdsec":  {"name": "Qwen2.5-3B + CrowdSec LoRA",  "precision": "int4", "repo": "patlegu/crowdsec-qwen25-onnx-int4"},
}

_ALL_AGENTS = ("opnsense", "wireguard", "crowdsec")


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
    for q in list(_sse_queues):
        await q.put(event)


def _sse_format(event: dict) -> str:
    return f"data: {json.dumps(event, ensure_ascii=False)}\n\n"


# ── Scénario ─────────────────────────────────────────────────────────────────

async def _run_scenario_task(scenario_id: str) -> None:
    global _scenario_running
    scenario = SCENARIOS[scenario_id]
    try:
        await _broadcast({"type": "scenario_start", "scenario_id": scenario_id})

        for step in scenario["steps"]:
            if _stop_event.is_set():
                break

            await _broadcast({
                "type": "step_start",
                "step_id": step["id"],
                "agent": step["agent"],
                "title": step["title"],
                "description": step["description"],
                "cap": step["cap"],
                "attack_edges": step.get("attack_edges", []),
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
        "pending": [a for a in _ALL_AGENTS if a not in runner._loaded],
        "models": _MODEL_INFO,
    }


@app.get("/api/scenarios")
async def list_scenarios():
    result = []
    for sid in SCENARIO_ORDER:
        s = SCENARIOS[sid]
        result.append({
            "id": s["id"],
            "title": s["title"],
            "description": s["description"],
            "tags": s.get("tags", []),
            "step_count": len(s["steps"]),
            "agents": list({step["agent"] for step in s["steps"]}),
        })
    return {"scenarios": result}


@app.get("/api/scenarios/{scenario_id}")
async def get_scenario(scenario_id: str):
    if scenario_id not in SCENARIOS:
        raise HTTPException(404, f"Scénario '{scenario_id}' introuvable")
    s = SCENARIOS[scenario_id]
    return {
        "id": s["id"],
        "title": s["title"],
        "description": s["description"],
        "tags": s.get("tags", []),
        "steps": [
            {
                "id": step["id"],
                "title": step["title"],
                "agent": step["agent"],
                "description": step["description"],
                "cap": step["cap"],
                "mitre": step.get("mitre"),
                "attack_edges": step.get("attack_edges", []),
            }
            for step in s["steps"]
        ],
    }


class RunRequest(BaseModel):
    scenario_id: str = "ssh_brute_force"


@app.post("/api/scenario/run")
async def run_scenario(req: RunRequest):
    global _scenario_running, _current_scenario_id
    if not runner.ready:
        raise HTTPException(503, "Modèles ONNX pas encore chargés")
    if _scenario_running:
        raise HTTPException(409, "Scénario déjà en cours")
    if req.scenario_id not in SCENARIOS:
        raise HTTPException(404, f"Scénario '{req.scenario_id}' introuvable")
    _stop_event.clear()
    _scenario_running = True
    _current_scenario_id = req.scenario_id
    asyncio.create_task(_run_scenario_task(req.scenario_id))
    return {"status": "started", "scenario_id": req.scenario_id}


@app.post("/api/scenario/reset")
async def reset_scenario():
    global _scenario_running, _current_scenario_id
    _stop_event.set()
    _scenario_running = False
    _current_scenario_id = None
    await _broadcast({"type": "scenario_reset"})
    return {"status": "reset"}


@app.get("/api/scenario/stream")
async def stream_events():
    q: asyncio.Queue = asyncio.Queue()
    _sse_queues.append(q)

    async def event_generator():
        try:
            while True:
                try:
                    event = await asyncio.wait_for(q.get(), timeout=15.0)
                    yield _sse_format(event)
                except asyncio.TimeoutError:
                    yield _sse_format({"type": "ping"})
        finally:
            _sse_queues.remove(q)

    return StreamingResponse(event_generator(), media_type="text/event-stream")


# ── Static files (frontend buildé) ───────────────────────────────────────────

_static_dir = Path(__file__).parent / "static"
if _static_dir.exists():
    app.mount("/", StaticFiles(directory=str(_static_dir), html=True), name="static")
