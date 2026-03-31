"""
executor.py — Exécution réelle des tool calls sur l'infrastructure live.

En mode live (BREACH_LIVE=1), après chaque inférence ONNX, le tool call JSON
produit par le modèle est exécuté contre les vraies APIs :

  Agent       Tool call             API cible
  ──────────  ────────────────────  ───────────────────────────────────────
  crowdsec    add_decision          CrowdSec LAPI  POST /v1/decisions
  opnsense    block_ip              OPNsense API   POST /api/firewall/filter/addRule
  opnsense    add_filter_rule       OPNsense API   POST /api/firewall/filter/addRule
  wireguard   add_wireguard_client  OPNsense API   POST /api/wireguard/client/addClient

En parallèle, l'attaque est déclenchée sur le poste infecté via SSH
avant l'inférence ONNX (pour que le contexte CAP reflète une vraie menace).
"""

import asyncio
import logging
from typing import Any

import asyncssh
import httpx

from .lab import LabConfig

logger = logging.getLogger(__name__)


# ── SSH : déclencher les attaques sur "infected" ──────────────────────────────

SCENARIO_ATTACK_COMMANDS: dict[str, dict[str, str]] = {
    "ssh_brute_force": {
        "step_1": "bash /opt/breach/ssh-brute.sh {srv_web_ip} &",
        "step_2": "bash /opt/breach/ssh-brute.sh {srv_web_ip} &",
        "step_3": "nmap -sS -p 1-1024 {srv_web_ip} &",
        "step_4": None,
    },
    "log4shell": {
        "step_1": "bash /opt/breach/log4shell.sh {srv_web_ip} &",
        "step_2": "bash /opt/breach/log4shell.sh {srv_web_ip} &",
        "step_3": "bash /opt/breach/log4shell.sh {srv_web_ip} &",
        "step_4": None,
    },
    "ddos_udp": {
        "step_1": "bash /opt/breach/ddos-udp.sh {srv_web_ip} 8 &",
        "step_2": "bash /opt/breach/ddos-udp.sh {srv_web_ip} 8 &",
        "step_3": None,
        "step_4": None,
    },
    "ransomware_c2": {
        "step_1": "bash /opt/breach/c2-beacon.sh &",
        "step_2": "bash /opt/breach/c2-beacon.sh &",
        "step_3": "bash /opt/breach/c2-beacon.sh &",
        "step_4": None,
    },
}


async def trigger_attack(lab: LabConfig, scenario_id: str, step_id: str) -> str | None:
    """Lance le script d'attaque correspondant sur la VM infected via SSH."""
    cmd_tpl = SCENARIO_ATTACK_COMMANDS.get(scenario_id, {}).get(step_id)
    if not cmd_tpl:
        return None

    cmd = cmd_tpl.format(
        srv_web_ip=lab.srv_web_ip,
        srv_db_ip=lab.srv_db_ip,
        infected_ip=lab.infected_ip,
    )

    try:
        async with asyncssh.connect(
            lab.infected_ip,
            username=lab.ssh_user,
            client_keys=[lab.ssh_key_path],
            known_hosts=None,
            connect_timeout=10,
        ) as conn:
            result = await conn.run(cmd, timeout=15)
            logger.info("SSH infected [%s/%s]: %s → exit %s", scenario_id, step_id, cmd, result.exit_status)
            return result.stdout.strip()
    except Exception as e:
        logger.warning("SSH infected failed [%s/%s]: %s", scenario_id, step_id, e)
        return None


# ── OPNsense REST API ─────────────────────────────────────────────────────────

def _opnsense_client(lab: LabConfig) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        base_url=lab.opnsense_api_url,
        auth=(lab.opnsense_api_key, lab.opnsense_api_secret),
        verify=lab.opnsense_verify_tls,
        timeout=15.0,
    )


async def opnsense_block_ip(lab: LabConfig, tool_args: dict) -> dict:
    """POST /api/firewall/filter/addRule — bloque une IP sur WAN."""
    ip = _extract(tool_args, "ip_address", "ip", "source_ip")
    interface = tool_args.get("interface", "wan")

    rule = {
        "rule": {
            "action": "block",
            "interface": interface,
            "ipprotocol": "inet",
            "protocol": "any",
            "src": ip,
            "dst": "any",
            "enabled": "1",
            "descr": f"breach-sim auto-block {ip}",
        }
    }
    async with _opnsense_client(lab) as client:
        r = await client.post("/firewall/filter/addRule", json=rule)
        r.raise_for_status()
        result = r.json()
        # Appliquer les changements
        await client.post("/firewall/filter/apply")
        logger.info("OPNsense block_ip %s → %s", ip, result)
        return result


async def opnsense_add_filter_rule(lab: LabConfig, tool_args: dict) -> dict:
    """POST /api/firewall/filter/addRule — ajoute une règle de filtrage."""
    src = _extract(tool_args, "source_subnet", "ip_subnet", "ip_address", default="any")
    dst_port = tool_args.get("destination_port", tool_args.get("port", "any"))
    interface = tool_args.get("interface", "wan")

    rule = {
        "rule": {
            "action": "block",
            "interface": interface,
            "ipprotocol": "inet",
            "protocol": "any",
            "src": src,
            "dst": "any",
            "dstport": str(dst_port),
            "enabled": "1",
            "descr": f"breach-sim filter {src}:{dst_port}",
        }
    }
    async with _opnsense_client(lab) as client:
        r = await client.post("/firewall/filter/addRule", json=rule)
        r.raise_for_status()
        result = r.json()
        await client.post("/firewall/filter/apply")
        logger.info("OPNsense add_filter_rule %s:%s → %s", src, dst_port, result)
        return result


async def opnsense_add_wireguard_client(lab: LabConfig, tool_args: dict) -> dict:
    """POST /api/wireguard/client/addClient — crée un peer WireGuard."""
    # tool_args peut être imbriqué sous "client_data"
    data = tool_args.get("client_data", tool_args)

    payload = {
        "client": {
            "enabled": "1",
            "name": data.get("name", "breach-client"),
            "tunneladdress": data.get("tunneladdress", "10.0.99.15/32"),
            "serveraddress": data.get("serveraddress", ""),
            "serverport": str(data.get("serverport", 51820)),
            "keepalive": str(data.get("keepalive", 25)),
        }
    }
    async with _opnsense_client(lab) as client:
        r = await client.post("/wireguard/client/addClient", json=payload)
        r.raise_for_status()
        result = r.json()
        await client.post("/wireguard/service/reconfigure")
        logger.info("OPNsense wireguard addClient %s → %s", data.get("name"), result)
        return result


# ── CrowdSec LAPI ─────────────────────────────────────────────────────────────

async def crowdsec_add_decision(lab: LabConfig, tool_args: dict) -> dict:
    """POST /v1/decisions — bannit une IP via CrowdSec LAPI."""
    ip = _extract(tool_args, "ip_address", "ip", "source_ip")
    duration = tool_args.get("duration", "24h")
    reason = tool_args.get("reason", "breach-sim")

    payload = [{
        "duration": duration,
        "ip": ip,
        "reason": reason,
        "scenario": "breach-sim/auto",
        "scope": "Ip",
        "type": "ban",
        "value": ip,
    }]

    headers = {"X-Api-Key": lab.crowdsec_api_key}
    async with httpx.AsyncClient(timeout=10.0) as client:
        r = await client.post(
            f"{lab.crowdsec_lapi_url}/v1/decisions",
            json=payload,
            headers=headers,
        )
        r.raise_for_status()
        logger.info("CrowdSec ban %s (%s) → %s", ip, duration, r.status_code)
        return {"banned": ip, "duration": duration}


# ── Dispatcher principal ──────────────────────────────────────────────────────

async def execute_tool_call(lab: LabConfig, agent: str, tool_call: dict) -> dict | None:
    """
    Exécute un tool call ONNX contre l'infrastructure réelle.
    Retourne le résultat de l'API, ou None si tool call non reconnu.
    """
    if not tool_call or "raw" in tool_call:
        logger.warning("Tool call non parseable — skip exécution live")
        return None

    # Normaliser : supporter {type, function} ou {function: {name, arguments}}
    fn = tool_call.get("function", {})
    name = fn.get("name", tool_call.get("name", ""))
    raw_args = fn.get("arguments", tool_call.get("arguments", {}))

    # arguments peut être une string JSON
    if isinstance(raw_args, str):
        import json
        try:
            args = json.loads(raw_args)
        except Exception:
            args = {}
    else:
        args = raw_args

    logger.info("Exécution live — agent=%s tool=%s args=%s", agent, name, args)

    try:
        if name == "add_decision" or (agent == "crowdsec" and "ip" in str(args).lower()):
            return await crowdsec_add_decision(lab, args)

        if name == "block_ip":
            return await opnsense_block_ip(lab, args)

        if name == "add_filter_rule":
            return await opnsense_add_filter_rule(lab, args)

        if name == "add_wireguard_client":
            return await opnsense_add_wireguard_client(lab, args)

    except httpx.HTTPStatusError as e:
        logger.error("API HTTP error [%s/%s]: %s — %s", agent, name, e.response.status_code, e.response.text)
        return {"error": f"HTTP {e.response.status_code}", "detail": e.response.text[:200]}
    except Exception as e:
        logger.error("Executor error [%s/%s]: %s", agent, name, e)
        return {"error": str(e)}

    logger.warning("Tool call non mappé : agent=%s name=%s", agent, name)
    return None


# ── Utilitaire ────────────────────────────────────────────────────────────────

def _extract(d: dict, *keys: str, default: str = "") -> str:
    """Retourne la première clé trouvée dans le dict, sinon default."""
    for k in keys:
        if k in d and d[k]:
            v = d[k]
            # Si c'est une liste, prendre le premier élément
            return v[0] if isinstance(v, list) else str(v)
    return default
