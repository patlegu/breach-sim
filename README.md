# breach-sim

Interactive simulation of a network attack blocked in real-time by 3 ONNX CPU-inference agents (OPNsense · WireGuard · CrowdSec)

## Overview

breach-sim visualizes a 3-step attack scenario where AI agents respond autonomously:

1. **Brute-force SSH detected** → CrowdSec agent bans the attacker IP
2. **IP still active** → OPNsense agent adds a firewall block rule
3. **Port scan detected** → OPNsense agent adds a filter rule for the subnet

Each step shows the CAP v1 packet sent to the agent, the ONNX inference token stream in real-time, and the resulting tool call JSON.

## Architecture

```
breach-sim/
├── backend/          # FastAPI — ONNX inference + SSE streaming
│   ├── main.py       # API endpoints + SSE broadcast
│   ├── onnx_runner.py # ONNX inference with async token streaming
│   ├── scenario.py   # Attack scenario definition (CAP v1 packets)
│   └── requirements.txt
├── frontend/         # Svelte 4 + Tailwind 3 + Cytoscape.js
│   └── src/
│       ├── App.svelte
│       └── lib/
│           ├── components/   # NetworkTopology, StepCard
│           ├── stores/       # scenarioStore, topologyStore
│           └── utils/        # demoApi (SSE + fetch)
├── scripts/
│   └── download_models.sh   # Download ONNX models from HuggingFace
└── start.sh                 # Auto-setup venv + launch backend
```

## Models

The 3 ONNX int4 CPU models are hosted on Hugging Face:

| Agent | Model | Size |
|---|---|---|
| OPNsense | [patlegu/opnsense-qwen25-onnx-int4](https://huggingface.co/patlegu/opnsense-qwen25-onnx-int4) | ~3 GB |
| WireGuard | [patlegu/wireguard-qwen25-onnx-int4](https://huggingface.co/patlegu/wireguard-qwen25-onnx-int4) | ~3 GB |
| CrowdSec | [patlegu/crowdsec-qwen25-onnx-int4](https://huggingface.co/patlegu/crowdsec-qwen25-onnx-int4) | ~3 GB |

Base model: `Qwen/Qwen2.5-3B-Instruct` fine-tuned with LoRA on cybersecurity function calling, merged and quantized to ONNX int4.

## Requirements

- Python 3.10+
- Node.js 18+
- ~10 GB disk (models) + ~1 GB RAM per model loaded
- CPU-only — no GPU required

## Installation

```bash
git clone https://github.com/patlegu/breach-sim
cd breach-sim

# Download ONNX models from HuggingFace (~9 GB total)
bash scripts/download_models.sh

# Build the frontend
cd frontend && npm install && npm run build && cd ..

# Launch
./start.sh
```

Open http://localhost:8888

## Configuration

| Variable | Default | Description |
|---|---|---|
| `ONNX_DIR` | `./onnx` | Path to ONNX models directory |
| `PORT` | `8888` | Listening port |

```bash
ONNX_DIR=/data/onnx PORT=9000 ./start.sh
```

## How it works

The backend loads all 3 ONNX models at startup (~30s). Once ready, the frontend activates the "Launch scenario" button.

Each inference step:
1. Builds a Qwen2.5 chat prompt from the CAP v1 packet
2. Runs `generate_next_token()` in a thread pool (non-blocking)
3. Streams each token to the frontend via SSE
4. Parses the resulting tool call JSON

Latency: ~8–12s per request on 8 vCPU CPU-only server.

## Related

- [cyber-agent-engine](https://github.com/patlegu/cyber-agent-engine) — multi-agent cybersecurity engine (vLLM + GPU)
- [CAP v1 protocol](https://github.com/patlegu/cyber-agent-engine/blob/main/roadmaps/AGENT_ARCHITECTURE_PARADIGM.md) — Coordinator-Agent Packet specification
