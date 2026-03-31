# ── module/classic-lab ────────────────────────────────────────────────────────
#
# 3 VMs Debian sur le réseau LAN isolé du lab :
#
#   srv-web   — Nginx (192.168.{10+id}.10)
#   srv-db    — PostgreSQL (192.168.{10+id}.20)
#   infected  — poste "compromis" (192.168.{10+id}.15)
#              scripts d'attaque contrôlés, installés mais non démarrés
#
# Toutes les VMs utilisent l'image Debian cloud (qcow2) en CoW.
# La config réseau (IP statique, gateway OPNsense, DNS) est injectée via
# cloud-init (NoCloud datasource — volume ISO séparé par VM).

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

locals {
  lan_prefix = split("/", var.lan_cidr)[1]
  gateway    = cidrhost(var.lan_cidr, 1)
  # Préfixe 192.168.X extrait du CIDR pour les templates cloud-init
  lan_base   = join(".", slice(split(".", cidrhost(var.lan_cidr, 0)), 0, 3))

  vms = {
    srv-web = {
      ip       = cidrhost(var.lan_cidr, 10)
      vcpu     = 1
      memory   = 1024
      disk     = 10737418240   # 10 GiB
      role     = "web"
    }
    srv-db = {
      ip       = cidrhost(var.lan_cidr, 20)
      vcpu     = 1
      memory   = 1024
      disk     = 10737418240
      role     = "db"
    }
    infected = {
      ip       = cidrhost(var.lan_cidr, 15)
      vcpu     = 1
      memory   = 1024
      disk     = 10737418240
      role     = "infected"
    }
  }
}

# ── Image de base Debian (téléchargée une fois) ───────────────────────────────

resource "terraform_data" "debian_base" {
  input = var.debian_image_url

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      CACHE="${var.image_cache_dir}"
      mkdir -p "$CACHE"
      BASE="$CACHE/debian-base.qcow2"
      if [ ! -f "$BASE" ]; then
        echo "==> Téléchargement image Debian cloud..."
        curl -fSL "${var.debian_image_url}" -o "$BASE"
        echo "==> Image de base prête : $BASE"
      fi
    EOT
  }
}

resource "terraform_data" "debian_base_volume" {
  # input stocke uri+pool pour les utiliser dans le destroy provisioner via self.input
  input = "${var.libvirt_uri}|${var.libvirt_pool}|${var.image_cache_dir}"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      VIRSH="virsh -c ${var.libvirt_uri}"
      if ! $VIRSH vol-info --pool ${var.libvirt_pool} debian-base.qcow2 >/dev/null 2>&1; then
        echo "==> Upload image Debian dans le pool libvirt..."
        $VIRSH vol-create-as ${var.libvirt_pool} debian-base.qcow2 10M --format qcow2
        $VIRSH vol-upload --pool ${var.libvirt_pool} debian-base.qcow2 \
          "${var.image_cache_dir}/debian-base.qcow2"
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      URI=$(echo "${self.input}" | cut -d'|' -f1)
      POOL=$(echo "${self.input}" | cut -d'|' -f2)
      virsh -c "$URI" vol-delete --pool "$POOL" debian-base.qcow2 2>/dev/null || true
    EOT
  }

  depends_on = [terraform_data.debian_base]
}

# ── Volumes disque (CoW depuis base) ─────────────────────────────────────────

resource "libvirt_volume" "vm" {
  for_each = local.vms

  name             = "breach-${var.instance_id}-${each.key}.qcow2"
  pool             = var.libvirt_pool
  base_volume_name = "debian-base.qcow2"
  base_volume_pool = var.libvirt_pool
  format           = "qcow2"
  size             = each.value.disk

  depends_on = [terraform_data.debian_base_volume]
}

# ── Cloud-init (NoCloud) ─────────────────────────────────────────────────────

resource "libvirt_cloudinit_disk" "vm" {
  for_each = local.vms

  name = "breach-${var.instance_id}-${each.key}-init.iso"
  pool = var.libvirt_pool

  user_data = templatefile("${path.module}/templates/user-data-${each.value.role}.yaml.tftpl", {
    hostname       = "breach${var.instance_id}-${each.key}"
    ssh_public_key = var.ssh_public_key
    instance_id    = var.instance_id
    lan_base       = local.lan_base
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    ip      = each.value.ip
    prefix  = local.lan_prefix
    gateway = local.gateway
  })
}

# ── Domaines libvirt ──────────────────────────────────────────────────────────

resource "libvirt_domain" "vm" {
  for_each = local.vms

  name   = "breach-${var.instance_id}-${each.key}"
  vcpu   = each.value.vcpu
  memory = each.value.memory

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.vm[each.key].id
    scsi      = false
  }

  cloudinit = libvirt_cloudinit_disk.vm[each.key].id

  network_interface {
    network_id     = var.lan_network_id
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  qemu_agent = true
  autostart  = true
}
