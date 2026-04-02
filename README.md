# breach-sim

Interactive simulation of network attacks blocked in real-time by 3 ONNX CPU-inference AI agents (OPNsense · WireGuard · CrowdSec)

## Overview

breach-sim demonstrates AI-driven cybersecurity response across 4 attack scenarios. Each scenario runs 3 sequential steps: the AI agent receives a CAP v1 packet, performs ONNX inference, and emits a tool call that can be executed against a real lab.

| Scenario | Attack | Agents involved |
|---|---|---|
| SSH Brute Force | Dictionary attack on SSH | CrowdSec → OPNsense |
| Log4Shell | JNDI payload in HTTP header | OPNsense → WireGuard |
| DDoS UDP Flood | hping3 flood | OPNsense → CrowdSec |
| Ransomware C2 | Cobalt Strike beacon + lateral movement | CrowdSec → OPNsense → WireGuard |

Two operating modes:
- **Simulated** (default) — inference only, tool calls are displayed but not executed
- **Live** — tool calls executed against a real KVM lab (OPNsense API, CrowdSec LAPI, WireGuard)

## Architecture

```
breach-sim/
├── app/
│   ├── backend/
│   │   ├── main.py          # FastAPI — SSE streaming, scenario runner
│   │   ├── onnx_runner.py   # ONNX int4 inference, async token streaming
│   │   ├── scenario.py      # 4 attack scenarios (CAP v1 packets)
│   │   ├── lab.py           # Lab config (live mode, IPs, credentials)
│   │   ├── executor.py      # Real API execution (OPNsense, CrowdSec, WireGuard, SSH)
│   │   └── requirements.txt
│   ├── frontend/            # Svelte 4 + Tailwind 3 + Cytoscape.js
│   │   └── src/
│   │       ├── App.svelte
│   │       └── lib/
│   │           ├── components/  # NetworkTopology, StepCard, ScenarioSelector
│   │           ├── stores/      # scenarioStore, topologyStore, animStore
│   │           └── utils/       # demoApi (SSE + fetch)
│   ├── scripts/
│   │   ├── download_models.sh
│   │   └── check_requirements.sh
│   └── start.sh             # Auto-setup venv + launch
├── infra/                   # KVM/libvirt labs (OpenTofu)
│   ├── Makefile
│   ├── envs/
│   │   └── classic/         # OPNsense + DMZ (T-Pot + srv-web) + LAN (srv-db + srv-app)
│   └── modules/
│       ├── network/         # libvirt networks (WAN NAT + DMZ isolated + LAN isolated)
│       ├── opnsense/        # OPNsense VM (config.xml push via SSH DMZ)
│       ├── classic-lab/     # 3 Debian VMs cloud-init (srv-web, srv-db, srv-app)
│       └── tpot/            # T-Pot CE honeypot VM (DMZ .50)
├── deploy/
│   ├── breach-sim.service   # systemd unit
│   ├── Caddyfile.snippet    # Caddy reverse proxy
│   └── install.sh
└── Makefile                 # Root shortcuts
```

## Models

3 ONNX int4 CPU models hosted on Hugging Face:

| Agent | Model | Size |
|---|---|---|
| OPNsense | [patlegu/opnsense-qwen25-onnx-int4](https://huggingface.co/patlegu/opnsense-qwen25-onnx-int4) | ~3 GB |
| WireGuard | [patlegu/wireguard-qwen25-onnx-int4](https://huggingface.co/patlegu/wireguard-qwen25-onnx-int4) | ~3 GB |
| CrowdSec | [patlegu/crowdsec-qwen25-onnx-int4](https://huggingface.co/patlegu/crowdsec-qwen25-onnx-int4) | ~3 GB |

Base: `Qwen/Qwen2.5-3B-Instruct` fine-tuned with LoRA on cybersecurity function calling, merged and quantized to ONNX int4.

## Requirements

- Python 3.10+
- Node.js 18+
- ~10 GB disk (models) + ~1 GB RAM per model
- CPU-only — no GPU required

**For live mode (optional):**
- libvirt/KVM host (Linux)
- OpenTofu 1.7+
- virsh, qemu-img, bunzip2
- ssh, scp (push config.xml vers OPNsense)

## Quick Start

```bash
git clone https://github.com/patlegu/breach-sim
cd breach-sim

# Check requirements
bash app/scripts/check_requirements.sh

# Download ONNX models (~9 GB)
make models

# Build frontend
make build

# Launch (simulated mode)
make dev
```

Open http://localhost:8888

## Configuration

| Variable | Default | Description |
|---|---|---|
| `ONNX_DIR` | `./onnx` | Path to ONNX models directory |
| `PORT` | `8888` | Listening port |

```bash
ONNX_DIR=/data/onnx PORT=9000 make dev
```

## Live Mode (KVM Lab)

Live mode connects the AI agents to a real isolated network running on KVM/libvirt.

### Lab topology (classic)

```
Internet (NAT)
     │
  OPNsense (vtnet1=WAN DHCP, vtnet0=DMZ 192.168.1.1, vtnet2=LAN 192.168.21.1)
     │
     ├── DMZ 192.168.1.0/24 (isolated)
     │    ├── T-Pot CE  192.168.1.50   (honeypot — Cowrie SSH, Dionaea, Kibana)
     │    └── srv-web   192.168.1.10   (Nginx)
     │
     └── LAN 192.168.21.0/24 (isolated)
          ├── srv-db    192.168.21.10  (PostgreSQL)
          └── srv-app   192.168.21.20  (app server)

WAN : 10.0.<INSTANCE>.0/24 (NAT libvirt)
LAN : 192.168.<20+INSTANCE>.0/24 — multi-instance sans conflit de routes
```

Management SSH depuis l'hyperviseur :
- OPNsense DMZ : `ssh -o BindAddress=192.168.1.254 root@192.168.1.1`
- T-Pot : `ssh -b 192.168.1.254 breach@192.168.1.50` (port 64295 après installation)
- VMs LAN : via OPNsense en proxy jump

> **Bootstrap OPNsense** : avec la golden image (`opnsense-golden.qcow2` dans le cache), SSH est disponible dès le premier boot — `tofu apply` pousse `config.xml` automatiquement. Sans golden image, bootstrap console requis une seule fois (voir `infra/modules/opnsense/main.tf`).

### Deploy a lab

```bash
# Copy and fill in credentials
cp infra/envs/classic/terraform.tfvars.example infra/envs/classic/terraform.tfvars

# Create lab instance 1
make lab-up LAB=classic INSTANCE=1

# Show IPs
make lab-show LAB=classic INSTANCE=1

# Destroy
make lab-down LAB=classic INSTANCE=1
```

### Enable live mode

```bash
BREACH_LIVE=1 \
BREACH_INSTANCE=1 \
OPNSENSE_API_KEY=<key> \
OPNSENSE_API_SECRET=<secret> \
make dev
```

When live, each tool call is executed against the real lab and the result is displayed alongside the inference output.

## How it works

At startup the backend loads all 3 ONNX models (~30s). Each inference step:

1. Builds a Qwen2.5 chat prompt from the CAP v1 packet
2. Runs `generate_next_token()` in a thread pool
3. Streams tokens to the frontend via SSE
4. Parses the tool call JSON
5. In live mode: executes the call against OPNsense/CrowdSec/WireGuard APIs

Latency: ~8–12s per step on 8 vCPU CPU-only server.

## Related

- [cyber-agent-engine](https://github.com/patlegu/cyber-agent-engine) — multi-agent cybersecurity engine (vLLM + GPU)
- [CAP v1 protocol](https://github.com/patlegu/cyber-agent-engine/blob/main/roadmaps/AGENT_ARCHITECTURE_PARADIGM.md) — Coordinator-Agent Packet specification
