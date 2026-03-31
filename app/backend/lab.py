"""
lab.py — Configuration du lab actif pour breach-sim.

En mode live, breach-sim se connecte à un lab KVM réel dont les IPs
sont lues depuis l'environnement (ou terraform output).

Variables d'environnement :
    BREACH_LIVE=1                  activer le mode live
    BREACH_LAB_TYPE=classic|k8s    type de lab
    BREACH_INSTANCE=1              numéro d'instance

    # OPNsense
    BREACH_OPNSENSE_IP             IP LAN OPNsense (ex: 192.168.11.1)
    BREACH_OPNSENSE_API_KEY        clé API REST
    BREACH_OPNSENSE_API_SECRET     secret API REST

    # CrowdSec LAPI (tourne sur OPNsense via plugin)
    BREACH_CROWDSEC_IP             IP LAPI CrowdSec (= OPNsense IP par défaut)
    BREACH_CROWDSEC_API_KEY        bouncer API key

    # SSH vers les VMs (même clé pour toutes)
    BREACH_SSH_KEY_PATH            chemin clé privée SSH (défaut: ~/.ssh/id_ed25519)
    BREACH_SSH_USER                user SSH (défaut: breach)

    # VMs
    BREACH_INFECTED_IP             IP du poste infecté
    BREACH_SRV_WEB_IP              IP srv-web
    BREACH_SRV_DB_IP               IP srv-db
    BREACH_K3S_CP_IP               IP control-plane k3s (lab k8s uniquement)
"""

import os
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class LabConfig:
    live: bool = False
    lab_type: str = "classic"   # classic | k8s
    instance: int = 1

    # OPNsense
    opnsense_ip: str = ""
    opnsense_api_key: str = ""
    opnsense_api_secret: str = ""
    opnsense_verify_tls: bool = False   # self-signed par défaut

    # CrowdSec LAPI
    crowdsec_ip: str = ""
    crowdsec_api_key: str = ""
    crowdsec_port: int = 8080

    # SSH
    ssh_key_path: str = str(Path.home() / ".ssh" / "id_ed25519")
    ssh_user: str = "breach"

    # VMs
    infected_ip: str = ""
    srv_web_ip: str = ""
    srv_db_ip: str = ""
    k3s_cp_ip: str = ""

    @property
    def opnsense_api_url(self) -> str:
        return f"https://{self.opnsense_ip}/api"

    @property
    def crowdsec_lapi_url(self) -> str:
        return f"http://{self.crowdsec_ip}:{self.crowdsec_port}"


def load_lab_config() -> LabConfig:
    """Charge la config lab depuis les variables d'environnement."""
    env = os.environ.get

    instance = int(env("BREACH_INSTANCE", "1"))
    # Calcul des IPs par défaut depuis l'instance si non surchargées
    lan_base = f"192.168.{10 + instance}"

    cfg = LabConfig(
        live=env("BREACH_LIVE", "0") == "1",
        lab_type=env("BREACH_LAB_TYPE", "classic"),
        instance=instance,

        opnsense_ip=env("BREACH_OPNSENSE_IP", f"{lan_base}.1"),
        opnsense_api_key=env("BREACH_OPNSENSE_API_KEY", ""),
        opnsense_api_secret=env("BREACH_OPNSENSE_API_SECRET", ""),
        opnsense_verify_tls=env("BREACH_OPNSENSE_VERIFY_TLS", "0") == "1",

        crowdsec_ip=env("BREACH_CROWDSEC_IP", f"{lan_base}.1"),
        crowdsec_api_key=env("BREACH_CROWDSEC_API_KEY", ""),

        ssh_key_path=env("BREACH_SSH_KEY_PATH", str(Path.home() / ".ssh" / "id_ed25519")),
        ssh_user=env("BREACH_SSH_USER", "breach"),

        infected_ip=env("BREACH_INFECTED_IP", f"{lan_base}.15"),
        srv_web_ip=env("BREACH_SRV_WEB_IP", f"{lan_base}.10"),
        srv_db_ip=env("BREACH_SRV_DB_IP", f"{lan_base}.20"),
        k3s_cp_ip=env("BREACH_K3S_CP_IP", f"{lan_base}.30"),
    )
    return cfg


# Singleton chargé au démarrage
lab = load_lab_config()
