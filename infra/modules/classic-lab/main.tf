# ── module/classic-lab ────────────────────────────────────────────────────────
#
# 3 VMs Debian réparties entre DMZ et LAN :
#
#   DMZ (192.168.{10+id}.0/24) — exposée via OPNsense :
#     srv-web  .10 — Nginx (frontal HTTP)
#
#   LAN (192.168.{20+id}.0/24) — isolée :
#     srv-db   .10 — PostgreSQL
#     srv-app  .20 — serveur applicatif Flask (cible passive)
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
  dmz_prefix  = split("/", var.dmz_cidr)[1]
  lan_prefix  = split("/", var.lan_cidr)[1]
  dmz_gateway = cidrhost(var.dmz_cidr, 1)
  lan_gateway = cidrhost(var.lan_cidr, 1)
  dmz_base    = join(".", slice(split(".", cidrhost(var.dmz_cidr, 0)), 0, 3))
  lan_base    = join(".", slice(split(".", cidrhost(var.lan_cidr, 0)), 0, 3))

  vms = {
    srv-web = {
      ip         = cidrhost(var.dmz_cidr, 10)
      prefix     = local.dmz_prefix
      gateway    = local.dmz_gateway
      network_id = var.dmz_network_id
      net_base   = local.dmz_base
      vcpu       = 1
      memory     = 1024
      disk       = 10737418240   # 10 GiB
      role       = "web"
    }
    srv-db = {
      ip         = cidrhost(var.lan_cidr, 10)
      prefix     = local.lan_prefix
      gateway    = local.lan_gateway
      network_id = var.lan_network_id
      net_base   = local.lan_base
      vcpu       = 1
      memory     = 1024
      disk       = 10737418240
      role       = "db"
    }
    srv-app = {
      ip         = cidrhost(var.lan_cidr, 20)
      prefix     = local.lan_prefix
      gateway    = local.lan_gateway
      network_id = var.lan_network_id
      net_base   = local.lan_base
      vcpu       = 1
      memory     = 1024
      disk       = 10737418240
      role       = "app"
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
# Le provider libvirt ne diff pas le contenu de user_data — on utilise un
# terraform_data avec triggers_replace pour forcer le remplacement du disque
# cloud-init dès que le contenu change (mot de passe, clé SSH, template...).

resource "terraform_data" "cloudinit_hash" {
  for_each = local.vms

  triggers_replace = sha256(join("|", [
    templatefile("${path.module}/templates/user-data-${each.value.role}.yaml.tftpl", {
      hostname         = "breach${var.instance_id}-${each.key}"
      ssh_public_key   = var.ssh_public_key
      vm_password_hash = var.vm_password_hash
      instance_id      = var.instance_id
      net_base         = each.value.net_base
    }),
    templatefile("${path.module}/templates/network-config.yaml.tftpl", {
      ip      = each.value.ip
      prefix  = each.value.prefix
      gateway = each.value.gateway
    }),
  ]))
}

resource "libvirt_cloudinit_disk" "vm" {
  for_each = local.vms

  name = "breach-${var.instance_id}-${each.key}-init.iso"
  pool = var.libvirt_pool

  depends_on = [terraform_data.debian_base_volume]

  user_data = templatefile("${path.module}/templates/user-data-${each.value.role}.yaml.tftpl", {
    hostname         = "breach${var.instance_id}-${each.key}"
    ssh_public_key   = var.ssh_public_key
    vm_password_hash = var.vm_password_hash
    instance_id      = var.instance_id
    net_base         = each.value.net_base
  })

  network_config = templatefile("${path.module}/templates/network-config.yaml.tftpl", {
    ip      = each.value.ip
    prefix  = each.value.prefix
    gateway = each.value.gateway
  })

  lifecycle {
    replace_triggered_by = [terraform_data.cloudinit_hash[each.key]]
  }
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

  # Réseau selon la zone (DMZ ou LAN) — défini dans local.vms
  network_interface {
    network_id     = each.value.network_id
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
      libvirt_cloudinit_disk.vm[each.key],
      libvirt_volume.vm[each.key],
    ]
  }
}
