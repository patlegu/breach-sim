# ── module/opnsense ───────────────────────────────────────────────────────────
#
# VM OPNsense sur KVM/libvirt.
#
# Interfaces :
#   em0 → WAN (NAT libvirt, DHCP)
#   em1 → LAN (isolated, IP statique configurée via config XML OPNsense)
#
# Bootstrap :
#   OPNsense ne supporte pas cloud-init. On injecte la config initiale via
#   une image "config drive" au format ISO (libvirt_cloudinit_disk avec
#   type = "nocloud" n'est pas compatible FreeBSD — on utilise un volume
#   raw contenant /conf/config.xml monté comme CD-ROM).
#
#   À la première installation, OPNsense lit /conf/config.xml depuis le
#   CD-ROM de configuration si présent. Ce fichier pré-configure :
#     - IP LAN (em1) statique
#     - mot de passe root (hashé SHA512)
#     - clé SSH autorisée
#     - API key + secret (pour le REST API)
#     - plugins CrowdSec + WireGuard listés dans le fichier de config
#
# Après le premier boot, la config est persistée sur le disque OPNsense.

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

locals {
  name       = "breach-${var.instance_id}-opnsense"
  lan_ip     = cidrhost(var.lan_cidr, 1)          # .1 = gateway LAN
  lan_prefix = split("/", var.lan_cidr)[1]
}

# ── Image de base OPNsense (qcow2) ───────────────────────────────────────────
# L'image nano/vga OPNsense est téléchargée une seule fois dans le pool libvirt.
# On crée ensuite un volume par instance (copy-on-write depuis la base).

resource "terraform_data" "opnsense_base" {
  input = var.opnsense_image_url

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      CACHE="${var.image_cache_dir}"
      mkdir -p "$CACHE"
      BASE_IMG="$CACHE/opnsense-base.qcow2"
      if [ ! -f "$BASE_IMG" ]; then
        echo "==> Téléchargement image OPNsense..."
        curl -fSL "${var.opnsense_image_url}" -o "$CACHE/opnsense.img.bz2"
        echo "==> Décompression..."
        bunzip2 "$CACHE/opnsense.img.bz2"
        echo "==> Conversion en qcow2..."
        qemu-img convert -f raw -O qcow2 "$CACHE/opnsense.img" "$BASE_IMG"
        rm -f "$CACHE/opnsense.img"
        echo "==> Image de base prête : $BASE_IMG"
      fi
    EOT
  }
}

resource "terraform_data" "opnsense_base_volume" {
  input = "${var.libvirt_uri}|${var.libvirt_pool}|${var.image_cache_dir}"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      VIRSH="virsh -c ${var.libvirt_uri}"
      BASE="opnsense-base.qcow2"
      if ! $VIRSH vol-info --pool ${var.libvirt_pool} "$BASE" >/dev/null 2>&1; then
        echo "==> Upload image de base dans le pool libvirt..."
        $VIRSH vol-create-as ${var.libvirt_pool} "$BASE" 10M --format qcow2
        $VIRSH vol-upload --pool ${var.libvirt_pool} "$BASE" "${var.image_cache_dir}/opnsense-base.qcow2"
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      URI=$(echo "${self.input}" | cut -d'|' -f1)
      POOL=$(echo "${self.input}" | cut -d'|' -f2)
      virsh -c "$URI" vol-delete --pool "$POOL" opnsense-base.qcow2 2>/dev/null || true
    EOT
  }

  depends_on = [terraform_data.opnsense_base]
}

# ── Volume disque OPNsense (CoW depuis la base) ───────────────────────────────

resource "libvirt_volume" "opnsense" {
  name             = "${local.name}.qcow2"
  pool             = var.libvirt_pool
  base_volume_name = "opnsense-base.qcow2"
  base_volume_pool = var.libvirt_pool
  format           = "qcow2"
  size             = var.disk_size

  depends_on = [terraform_data.opnsense_base_volume]
}

# ── Config drive ISO (config.xml initial) ─────────────────────────────────────
# Génère l'ISO de configuration OPNsense avec config.xml pré-rempli.
# Monté comme CD-ROM au premier boot.

resource "terraform_data" "config_iso" {
  # uri|pool|instance_id pour le destroy provisioner (self.input uniquement)
  input = "${var.libvirt_uri}|${var.libvirt_pool}|${var.instance_id}"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      WORKDIR=$(mktemp -d)
      mkdir -p "$WORKDIR/conf"

      cat > "$WORKDIR/conf/config.xml" << 'XMLEOF'
${templatefile("${path.module}/templates/config.xml.tftpl", {
        lan_ip      = local.lan_ip
        lan_prefix  = local.lan_prefix
        root_hash   = var.root_password_hash
        ssh_key     = var.ssh_public_key
        api_key     = var.api_key
        api_secret  = var.api_secret
        hostname    = "opnsense-${var.instance_id}"
      })}
XMLEOF

      ISO="${var.image_cache_dir}/breach-${var.instance_id}-opnsense-conf.iso"
      mkisofs -o "$ISO" -r -J "$WORKDIR"
      rm -rf "$WORKDIR"
      echo "==> Config ISO générée : $ISO"

      VIRSH="virsh -c ${var.libvirt_uri}"
      VOLNAME="breach-${var.instance_id}-opnsense-conf.iso"
      if $VIRSH vol-info --pool ${var.libvirt_pool} "$VOLNAME" >/dev/null 2>&1; then
        $VIRSH vol-delete --pool ${var.libvirt_pool} "$VOLNAME"
      fi
      $VIRSH vol-create-as ${var.libvirt_pool} "$VOLNAME" 10M --format raw
      $VIRSH vol-upload --pool ${var.libvirt_pool} "$VOLNAME" "$ISO"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      URI=$(echo "${self.input}" | cut -d'|' -f1)
      POOL=$(echo "${self.input}" | cut -d'|' -f2)
      INST=$(echo "${self.input}" | cut -d'|' -f3)
      virsh -c "$URI" vol-delete --pool "$POOL" \
        "breach-$INST-opnsense-conf.iso" 2>/dev/null || true
    EOT
  }
}

# Référence au volume ISO dans libvirt
data "libvirt_volume" "config_iso" {
  name = "breach-${var.instance_id}-opnsense-conf.iso"
  pool = var.libvirt_pool

  depends_on = [terraform_data.config_iso]
}

# ── Domaine libvirt OPNsense ──────────────────────────────────────────────────

resource "libvirt_domain" "opnsense" {
  name   = local.name
  vcpu   = var.vcpu
  memory = var.memory_mb

  cpu {
    mode = "host-passthrough"
  }

  # Disque principal
  disk {
    volume_id = libvirt_volume.opnsense.id
    scsi      = false
  }

  # CD-ROM config (éjecté après premier boot — OPNsense persiste la config)
  disk {
    volume_id = data.libvirt_volume.config_iso.id
    scsi      = false
  }

  # em0 — WAN
  network_interface {
    network_id     = var.wan_network_id
    wait_for_lease = true
  }

  # em1 — LAN
  network_interface {
    network_id     = var.lan_network_id
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

  autostart = true

  depends_on = [terraform_data.config_iso]
}
