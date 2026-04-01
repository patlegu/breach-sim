# ── module/network ────────────────────────────────────────────────────────────
#
# Crée trois réseaux libvirt pour un lab breach-sim :
#
#   breach-{id}-wan  (NAT, 10.0.{id}.0/24)
#     └── OPNsense vtnet0 (WAN) — IP statique 10.0.{id}.2
#         Masquerade sortant vers l'interface physique du serveur
#
#   breach-{id}-dmz  (isolated, 192.168.{10+id}.0/24)
#     └── OPNsense vtnet1 (DMZ) — 192.168.{10+id}.1
#         T-Pot (honeypot), srv-web
#         Exposée à internet via port forwards OPNsense + DNAT korrig
#
#   breach-{id}-lan  (isolated, 192.168.{20+id}.0/24)
#     └── OPNsense vtnet2 (LAN) — 192.168.{20+id}.1
#         srv-db, srv-app
#         Isolée, non accessible depuis internet ni la DMZ
#
# DHCP libvirt désactivé sur DMZ et LAN — OPNsense fait office de DHCP.
# Le bridge host reçoit la dernière IP du subnet (.254) via provisioner.

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

# ── DMZ — isolée, routée par OPNsense, exposée à internet ────────────────────

resource "libvirt_network" "dmz" {
  name      = "breach-${var.instance_id}-dmz"
  mode      = "none"
  autostart = true

  dhcp {
    enabled = false
  }
}

# ── LAN — isolé, routé par OPNsense, non accessible depuis internet ───────────

resource "libvirt_network" "lan" {
  name      = "breach-${var.instance_id}-lan"
  mode      = "none"
  autostart = true

  dhcp {
    enabled = false
  }
}

# ── STP off + IP host sur DMZ et LAN ─────────────────────────────────────────
# Le bridge libvirt active STP par défaut (~30s de blocage après création VM).
# On désactive STP et on assigne la dernière IP du subnet au bridge host
# pour permettre l'accès management depuis korrig.

resource "terraform_data" "dmz_stp_off" {
  input = "${var.libvirt_uri}|${var.dmz_cidr}"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      BRIDGE=$(virsh -c ${var.libvirt_uri} net-info breach-${var.instance_id}-dmz \
        | awk '/Bridge:/{print $2}')
      if [ -n "$BRIDGE" ]; then
        ip link set "$BRIDGE" type bridge stp_state 0
        ip addr replace "${cidrhost(var.dmz_cidr, -2)}/${split("/", var.dmz_cidr)[1]}" dev "$BRIDGE"
        echo "==> DMZ bridge $BRIDGE : STP off, IP ${cidrhost(var.dmz_cidr, -2)}"
      fi
    EOT
  }

  depends_on = [libvirt_network.dmz]
}

resource "terraform_data" "lan_stp_off" {
  input = "${var.libvirt_uri}|${var.lan_cidr}"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      BRIDGE=$(virsh -c ${var.libvirt_uri} net-info breach-${var.instance_id}-lan \
        | awk '/Bridge:/{print $2}')
      if [ -n "$BRIDGE" ]; then
        ip link set "$BRIDGE" type bridge stp_state 0
        ip addr replace "${cidrhost(var.lan_cidr, -2)}/${split("/", var.lan_cidr)[1]}" dev "$BRIDGE"
        echo "==> LAN bridge $BRIDGE : STP off, IP ${cidrhost(var.lan_cidr, -2)}"
      fi
    EOT
  }

  depends_on = [libvirt_network.lan]
}
