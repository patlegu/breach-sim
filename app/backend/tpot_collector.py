"""
tpot_collector.py — Collecte temps réel des événements T-Pot depuis Elasticsearch.

Principe :
  - TpotCollector maintient le dernier @timestamp vu (_last_ts)
  - fetch_new_events() interroge ES pour les docs > _last_ts (tri asc)
  - Chaque appel retourne uniquement les nouveaux événements
  - Les compteurs par honeypot (_counts) sont cumulés en mémoire

Poll recommandé : 3s. La latence réelle dépend du pipeline Logstash (~5-15s).

Champs ES utilisés (communs à tous les honeypots T-Pot) :
  @timestamp, type, src_ip, dest_port (ou dst_port selon le honeypot)
"""

import ipaddress
import logging
from datetime import datetime, timezone
from typing import Any

import httpx

from .lab import LabConfig

logger = logging.getLogger(__name__)

# Taille max du batch par poll (évite de flood le SSE au démarrage)
_MAX_BATCH = 20


class TpotCollector:
    def __init__(self) -> None:
        self._last_ts: str = _now_minus_minutes(2)
        self._counts: dict[str, int] = {}

    @property
    def counts(self) -> list[dict[str, Any]]:
        """Leaderboard trié par hits desc."""
        return sorted(
            [{"name": k, "hits": v} for k, v in self._counts.items()],
            key=lambda x: x["hits"],
            reverse=True,
        )

    async def fetch_new_events(self, lab: LabConfig) -> list[dict[str, Any]]:
        """
        Retourne les nouveaux événements T-Pot depuis le dernier appel.
        Met à jour _last_ts et _counts.
        Retourne [] si ES est injoignable ou sans nouveaux docs.
        """
        url = f"http://{lab.tpot_ip}:{lab.tpot_es_port}/logstash-*/_search"
        query = {
            "size": _MAX_BATCH,
            "sort": [{"@timestamp": "asc"}],
            "query": {
                "range": {"@timestamp": {"gt": self._last_ts}},
            },
            "_source": ["@timestamp", "type", "src_ip", "dest_port", "dst_port"],
        }

        auth = (lab.tpot_es_user, lab.tpot_es_password) if lab.tpot_es_user else None

        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                r = await client.post(url, json=query, auth=auth)
                r.raise_for_status()
                hits = r.json().get("hits", {}).get("hits", [])
        except httpx.ConnectError:
            logger.debug("T-Pot ES injoignable (%s:%s)", lab.tpot_ip, lab.tpot_es_port)
            return []
        except Exception as e:
            logger.warning("T-Pot ES error: %s", e)
            return []

        if not hits:
            return []

        events: list[dict[str, Any]] = []
        for h in hits:
            src = h.get("_source", {})
            ts = src.get("@timestamp", "")
            honeypot = src.get("type", "unknown")
            src_ip = src.get("src_ip", "?")
            port = src.get("dest_port") or src.get("dst_port") or 0

            # Ignorer les IPs privées (NAT interne, WireGuard, etc.)
            if _is_private(src_ip):
                continue

            # Mise à jour compteurs
            self._counts[honeypot] = self._counts.get(honeypot, 0) + 1

            events.append({
                "ts": ts,
                "honeypot": honeypot,
                "src_ip": src_ip,
                "port": port,
            })

        # Avancer le curseur au dernier timestamp vu
        last_src = hits[-1].get("_source", {})
        if last_src.get("@timestamp"):
            self._last_ts = last_src["@timestamp"]

        return events


def _is_private(ip: str) -> bool:
    """Retourne True si l'IP est RFC 1918 / loopback / link-local."""
    try:
        return ipaddress.ip_address(ip).is_private
    except ValueError:
        return False


def _now_minus_minutes(n: int) -> str:
    """Retourne le timestamp ISO UTC il y a n minutes (point de départ du collecteur)."""
    from datetime import timedelta
    dt = datetime.now(timezone.utc) - timedelta(minutes=n)
    return dt.strftime("%Y-%m-%dT%H:%M:%S.000Z")
