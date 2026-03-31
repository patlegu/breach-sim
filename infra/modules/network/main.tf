# ── module/network ────────────────────────────────────────────────────────────
#
# Crée deux réseaux libvirt pour un lab breach-sim :
#
#   virbr-breach-{id}-wan  (NAT, 10.0.{id}.0/24)
#     └── OPNsense em0 (WAN) — obtient une IP par DHCP
#         Masquerade sortant vers l'interface physique du serveur
#
#   virbr-breach-{id}-lan  (isolated, 192.168.{10+id}.0/24)
#     └── OPNsense em1 (LAN) — 192.168.{10+id}.1 (statique, configuré dans OPNsense)
#         srv-web, srv-db, infected
#
# Le réseau LAN est isolé (mode="none") : tout le trafic passe par OPNsense.
# DHCP libvirt désactivé sur LAN — OPNsense fait office de DHCP.

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

# ── WAN — NAT vers l'extérieur ────────────────────────────────────────────────

resource "libvirt_network" "wan" {
  name      = "breach-${var.instance_id}-wan"
  mode      = "nat"
  autostart = true
  addresses = [var.wan_cidr]

  dhcp {
    enabled = true
  }

  dns {
    enabled    = false
    local_only = false
  }
}

# ── LAN — isolé, routé par OPNsense ──────────────────────────────────────────

resource "libvirt_network" "lan" {
  name      = "breach-${var.instance_id}-lan"
  mode      = "none"   # pas de NAT libvirt — OPNsense est le routeur
  autostart = true
  addresses = [var.lan_cidr]

  dhcp {
    enabled = false    # OPNsense gère le DHCP
  }
}
