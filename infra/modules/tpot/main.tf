# ── module/tpot ───────────────────────────────────────────────────────────────
#
# VM T-Pot honeypot dans la DMZ.
#
# T-Pot CE (telekom-security/tpotce) est installé via un service systemd
# oneshot au premier boot — l'installation prend ~30 min et se termine par
# un reboot automatique. Progression : journalctl -u tpot-install -f
#
# Ports importants après installation :
#   22    → honeypot SSH (Cowrie)
#   64295 → SSH management
#   64297 → T-Pot web UI (HTTPS)
#
# Prérequis : debian-base.qcow2 doit exister dans le pool libvirt.
#             En pratique ce module dépend de module.classic_lab via
#             depends_on dans l'environnement appelant.

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

locals {
  name    = "breach-${var.instance_id}-tpot"
  tpot_ip = cidrhost(var.dmz_cidr, 50)
  prefix  = split("/", var.dmz_cidr)[1]
  gateway = cidrhost(var.dmz_cidr, 1)
}

# ── Volume disque (CoW depuis debian-base) ────────────────────────────────────

resource "libvirt_volume" "tpot" {
  name             = "${local.name}.qcow2"
  pool             = var.libvirt_pool
  base_volume_name = "debian-base.qcow2"
  base_volume_pool = var.libvirt_pool
  format           = "qcow2"
  size             = var.disk_size
}

# ── Cloud-init ────────────────────────────────────────────────────────────────

resource "terraform_data" "cloudinit_hash" {
  triggers_replace = sha256(templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    hostname         = "breach${var.instance_id}-tpot"
    ssh_public_key   = var.ssh_public_key
    tpot_web_user    = var.tpot_web_user
    tpot_web_pw      = var.tpot_web_pw
    vm_password_hash = var.vm_password_hash
  }))
}

resource "libvirt_cloudinit_disk" "tpot" {
  name = "${local.name}-init.iso"
  pool = var.libvirt_pool

  user_data = templatefile("${path.module}/templates/user-data.yaml.tftpl", {
    hostname         = "breach${var.instance_id}-tpot"
    ssh_public_key   = var.ssh_public_key
    tpot_web_user    = var.tpot_web_user
    tpot_web_pw      = var.tpot_web_pw
    vm_password_hash = var.vm_password_hash
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    ip      = local.tpot_ip
    prefix  = local.prefix
    gateway = local.gateway
  })

  lifecycle {
    replace_triggered_by = [terraform_data.cloudinit_hash]
  }
}

# ── Domaine libvirt ───────────────────────────────────────────────────────────

resource "libvirt_domain" "tpot" {
  name   = local.name
  vcpu   = var.vcpu
  memory = var.memory_mb

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.tpot.id
    scsi      = false
  }

  cloudinit = libvirt_cloudinit_disk.tpot.id

  network_interface {
    network_id     = var.dmz_network_id
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }

  qemu_agent = true
  autostart  = true

  lifecycle {
    replace_triggered_by = [
      libvirt_cloudinit_disk.tpot,
      libvirt_volume.tpot,
    ]
  }
}
