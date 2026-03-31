# ── module/opnsense ───────────────────────────────────────────────────────────
#
# VM OPNsense sur KVM/libvirt.
#
# Interfaces (ordre libvirt → vtnet KVM) :
#   vtnet0 → WAN (NAT libvirt, DHCP) — première interface du domaine
#   vtnet1 → LAN (isolated, IP statique configurée via config.xml)
#
# Bootstrap :
#   OPNsense ne supporte pas cloud-init. La config est injectée via SSH
#   après le premier boot : config.xml est rendu localement puis poussé
#   via SCP sur /conf/config.xml, suivi d'un rechargement des services.
#
#   Premier déploiement : activer SSH manuellement via la console OPNsense
#   (menu option 14 ou /usr/sbin/sshd), ajouter la clé SSH de korrig dans
#   /root/.ssh/authorized_keys, puis relancer `tofu apply`.

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

locals {
  name       = "breach-${var.instance_id}-opnsense"
  lan_ip     = cidrhost(var.lan_cidr, 1)
  lan_prefix = split("/", var.lan_cidr)[1]
  dhcp_from  = cidrhost(var.lan_cidr, 10)
  dhcp_to    = cidrhost(var.lan_cidr, 99)

  config_xml = templatefile("${path.module}/templates/config.xml.tftpl", {
    hostname   = "breach${var.instance_id}-opnsense"
    root_hash  = var.root_password_hash
    ssh_key    = var.ssh_public_key
    api_key    = var.api_key
    api_secret = var.api_secret
    lan_ip     = local.lan_ip
    lan_prefix = local.lan_prefix
    dhcp_from  = local.dhcp_from
    dhcp_to    = local.dhcp_to
  })
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

# ── Rendu config.xml (local) ─────────────────────────────────────────────────

resource "local_sensitive_file" "opnsense_config" {
  content  = local.config_xml
  filename = "/tmp/breach-${var.instance_id}-opnsense-config.xml"
}

# ── Domaine libvirt OPNsense ──────────────────────────────────────────────────

resource "libvirt_domain" "opnsense" {
  name   = local.name
  vcpu   = var.vcpu
  memory = var.memory_mb

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.opnsense.id
    scsi      = false
  }

  # vtnet0 — WAN (OPNsense nano défaut : vtnet0=WAN, vtnet1=LAN)
  network_interface {
    network_id     = var.wan_network_id
    wait_for_lease = false
  }

  # vtnet1 — LAN
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
}

# ── Push config.xml via SSH ───────────────────────────────────────────────────
# Pousse config.xml sur OPNsense et recharge les services dès que le contenu
# change. Prérequis bootstrap (premier déploiement uniquement) :
#   1. Activer SSH sur OPNsense via la console (option 14 du menu)
#   2. Ajouter la clé SSH de korrig dans /root/.ssh/authorized_keys
#   3. Relancer `tofu apply`

resource "terraform_data" "opnsense_config_push" {
  triggers_replace = sha256(local.config_xml)

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      LAN_IP="${local.lan_ip}"
      CFG="${local_sensitive_file.opnsense_config.filename}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5"

      echo "==> Attente SSH OPNsense ($LAN_IP)..."
      for i in $(seq 1 30); do
        if ssh $SSH_OPTS root@$LAN_IP true 2>/dev/null; then
          echo "==> SSH disponible (tentative $i)"
          break
        fi
        echo "  tentative $i/30, retry dans 10s..."
        sleep 10
      done

      echo "==> Push config.xml..."
      scp $SSH_OPTS "$CFG" root@$LAN_IP:/conf/config.xml

      echo "==> Rechargement config OPNsense..."
      ssh $SSH_OPTS root@$LAN_IP \
        "configctl filter reload; /usr/local/sbin/pluginctl -s openssh restart" || true

      echo "==> Config OPNsense appliquée."
    EOT
  }

  depends_on = [libvirt_domain.opnsense, local_sensitive_file.opnsense_config]
}
