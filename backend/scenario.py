"""
scenario.py — Définition du scénario d'attaque en 4 étapes.

Chaque étape correspond à un paquet CAP v1 envoyé à un agent ONNX.
"""

SCENARIO_STEPS = [
    {
        "id": "step_1",
        "title": "Brute-force SSH détecté",
        "agent": "crowdsec",
        "description": "847 tentatives de connexion SSH en 60s depuis 185.220.101.47",
        "edge": ("attacker", "crowdsec"),
        "topology_event": "crowdsec_ban",
        "mitre": {
            "tactic": "Credential Access",
            "technique": "T1110",
            "name": "Brute Force",
            "cve": None,
        },
        "cap": {
            "directive": "add_decision",
            "entities": {
                "IP_ADDRESS": ["185.220.101.47"],
                "PORT_NUMBER": ["22"],
                "HOSTNAME": [],
            },
            "context": {
                "source": "siem",
                "reason": "brute_force_ssh",
                "confidence": 0.97,
                "attempts": 847,
                "timewindow": "60s",
            },
        },
        "expected_function": "add_decision",
    },
    {
        "id": "step_2",
        "title": "IP toujours active — blocage firewall",
        "agent": "opnsense",
        "description": "L'IP contourne le bouncer CrowdSec — blocage au niveau firewall",
        "edge": ("attacker", "firewall"),
        "topology_event": "firewall_block",
        "mitre": {
            "tactic": "Defense Evasion",
            "technique": "T1562.004",
            "name": "Disable or Modify System Firewall",
            "cve": None,
        },
        "cap": {
            "directive": "block_ip",
            "entities": {
                "IP_ADDRESS": ["185.220.101.47"],
                "INTERFACE": ["wan"],
                "PORT_NUMBER": [],
                "HOSTNAME": [],
                "IP_SUBNET": [],
            },
            "context": {
                "source": "crowdsec",
                "reason": "ban_evasion",
                "confidence": 0.95,
                "previous_action": "add_decision",
            },
        },
        "expected_function": "block_ip",
    },
    {
        "id": "step_3",
        "title": "Scan de ports détecté",
        "agent": "opnsense",
        "description": "Scan SYN stealth sur les ports 1-1024 depuis le subnet 185.220.101.0/24",
        "edge": ("attacker", "dmz"),
        "topology_event": "filter_rule_added",
        "mitre": {
            "tactic": "Discovery",
            "technique": "T1046",
            "name": "Network Service Discovery",
            "cve": None,
        },
        "cap": {
            "directive": "add_filter_rule",
            "entities": {
                "IP_ADDRESS": ["185.220.101.47"],
                "INTERFACE": ["wan"],
                "PORT_NUMBER": ["1-1024"],
                "HOSTNAME": [],
                "IP_SUBNET": ["185.220.101.0/24"],
            },
            "context": {
                "source": "ids",
                "reason": "port_scan",
                "confidence": 0.88,
                "scan_type": "syn_stealth",
            },
        },
        "expected_function": "add_filter_rule",
    },
    {
        "id": "step_4",
        "title": "Rotation des clés VPN",
        "agent": "wireguard",
        "description": "Pivot VPN détecté — rotation préventive des clés WireGuard",
        "edge": ("firewall", "wireguard"),
        "topology_event": "wireguard_rotate",
        "mitre": {
            "tactic": "Command and Control",
            "technique": "T1572",
            "name": "Protocol Tunneling",
            "cve": None,
        },
        "cap": {
            "directive": "generate_wireguard_keypair",
            "entities": {
                "HOSTNAME": ["vpn.lan"],
                "IP_ADDRESS": [],
                "IP_SUBNET": [],
            },
            "context": {
                "source": "opnsense",
                "reason": "vpn_pivot_detected",
                "confidence": 0.84,
                "trigger": "port_scan_subnet",
            },
        },
        "expected_function": "generate_wireguard_keypair",
    },
]
