# ── module/opnsense ───────────────────────────────────────────────────────────
#
# VM OPNsense sur KVM/libvirt.
#
# Interfaces (ordre libvirt → vtnet KVM) :
#   vtnet0 → DMZ (isolated, 192.168.1.0/24 = LAN défaut OPNsense → bootstrap SSH)
#   vtnet1 → WAN (NAT libvirt, DHCP)
#   vtnet2 → LAN (isolated, IP statique configurée via config.xml)
#
# Bootstrap :
#   OPNsense ne supporte pas cloud-init. La config est injectée via SSH
#   après le premier boot : config.xml est rendu localement puis poussé
#   via SCP sur /conf/config.xml, suivi d'un reboot.
#
#   Premier déploiement (une seule fois) :
#     1. virsh console → menu 8 (Shell)
#     2. ssh-keygen -A
#     3. /usr/local/sbin/sshd -f /usr/local/etc/ssh/sshd_config
#     4. echo "CLÉPUB" >> /root/.ssh/authorized_keys
#     5. Relancer `tofu apply`
#
#   Golden image (optionnel, supprime le bootstrap manuel) :
#     Après déploiement réussi, éteindre proprement :
#       virsh shutdown breach-N-opnsense && virsh domstate --wait breach-N-opnsense
#     Puis capturer :
#       virsh vol-download --pool images breach-N-opnsense.qcow2 /tmp/cow.qcow2
#       qemu-img convert -c -O qcow2 /tmp/cow.qcow2 <cache_dir>/opnsense-golden.qcow2

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
  # Si base_image_override est renseigné, on l'utilise tel quel (protège les instances existantes).
  # Sinon : auto-détection golden > base nano.
  base_image = var.base_image_override != "" ? var.base_image_override : (
    fileexists("${var.image_cache_dir}/opnsense-golden.qcow2") ? "opnsense-golden.qcow2" : "opnsense-base.qcow2"
  )
  dmz_ip     = cidrhost(var.dmz_cidr, 1)
  dmz_prefix = split("/", var.dmz_cidr)[1]
  lan_ip     = cidrhost(var.lan_cidr, 1)
  lan_prefix = split("/", var.lan_cidr)[1]
  # DHCP séparé par zone
  dmz_dhcp_from = cidrhost(var.dmz_cidr, 10)
  dmz_dhcp_to   = cidrhost(var.dmz_cidr, 99)
  lan_dhcp_from = cidrhost(var.lan_cidr, 10)
  lan_dhcp_to   = cidrhost(var.lan_cidr, 99)

  config_xml = templatefile("${path.module}/templates/config.xml.tftpl", {
    hostname      = "breach${var.instance_id}-opnsense"
    root_hash     = var.root_password_hash
    ssh_key       = var.ssh_public_key
    api_key       = var.api_key
    api_secret    = var.api_secret
    dmz_cidr      = var.dmz_cidr
    dmz_ip        = local.dmz_ip
    dmz_prefix    = local.dmz_prefix
    dmz_dhcp_from = local.dmz_dhcp_from
    dmz_dhcp_to   = local.dmz_dhcp_to
    lan_cidr      = var.lan_cidr
    lan_ip        = local.lan_ip
    lan_prefix    = local.lan_prefix
    lan_dhcp_from = local.lan_dhcp_from
    lan_dhcp_to   = local.lan_dhcp_to
  })
}

# ── Image de base OPNsense (qcow2) ───────────────────────────────────────────
# Priorité : golden image (opnsense-golden.qcow2) si présente dans le cache.
# Fallback : téléchargement de l'image nano OPNsense officielle.
# Golden image = capture d'une instance proprement arrêtée, SSH déjà configuré
# → supprime le bootstrap console pour toutes les instances suivantes.

resource "terraform_data" "opnsense_base" {
  input = var.image_cache_dir

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      CACHE="${var.image_cache_dir}"
      mkdir -p "$CACHE"
      GOLDEN="$CACHE/opnsense-golden.qcow2"
      BASE_IMG="$CACHE/opnsense-base.qcow2"
      if [ -f "$GOLDEN" ]; then
        echo "==> Golden image présente : $GOLDEN"
      elif [ ! -f "$BASE_IMG" ]; then
        echo "==> Téléchargement image OPNsense..."
        curl -fSL "${var.opnsense_image_url}" -o "$CACHE/opnsense.img.bz2"
        echo "==> Décompression..."
        bunzip2 "$CACHE/opnsense.img.bz2"
        echo "==> Conversion en qcow2..."
        qemu-img convert -f raw -O qcow2 "$CACHE/opnsense.img" "$BASE_IMG"
        rm -f "$CACHE/opnsense.img"
        echo "==> Image de base prête : $BASE_IMG"
      else
        echo "==> Image de base déjà présente : $BASE_IMG"
      fi
    EOT
  }
}

resource "terraform_data" "opnsense_base_volume" {
  input = "${var.libvirt_uri}|${var.libvirt_pool}|${var.image_cache_dir}|${local.base_image}"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      VIRSH="virsh -c ${var.libvirt_uri}"
      CACHE="${var.image_cache_dir}"
      GOLDEN="$CACHE/opnsense-golden.qcow2"
      if [ -f "$GOLDEN" ]; then
        BASE="opnsense-golden.qcow2"
        LOCAL_IMG="$GOLDEN"
      else
        BASE="opnsense-base.qcow2"
        LOCAL_IMG="$CACHE/opnsense-base.qcow2"
      fi
      if ! $VIRSH vol-info --pool ${var.libvirt_pool} "$BASE" >/dev/null 2>&1; then
        echo "==> Upload $BASE dans le pool libvirt..."
        SIZE=$(qemu-img info --output=json "$LOCAL_IMG" | python3 -c "import sys,json; print(json.load(sys.stdin)['virtual-size'])")
        $VIRSH vol-create-as ${var.libvirt_pool} "$BASE" "$SIZE" --format qcow2
        $VIRSH vol-upload --pool ${var.libvirt_pool} "$BASE" "$LOCAL_IMG"
        echo "==> $BASE uploadée."
      else
        echo "==> $BASE déjà présente dans le pool."
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      URI=$(echo "${self.input}" | cut -d'|' -f1)
      POOL=$(echo "${self.input}" | cut -d'|' -f2)
      BASE=$(echo "${self.input}" | cut -d'|' -f4)
      virsh -c "$URI" vol-delete --pool "$POOL" "$BASE" 2>/dev/null || true
    EOT
  }

  depends_on = [terraform_data.opnsense_base]
}

# ── Volume disque OPNsense (CoW depuis la base) ───────────────────────────────

resource "libvirt_volume" "opnsense" {
  name             = "${local.name}.qcow2"
  pool             = var.libvirt_pool
  base_volume_name = local.base_image
  base_volume_pool = var.libvirt_pool
  format           = "qcow2"
  size             = var.disk_size

  # Le provider libvirt ne relit pas la backing store lors d'un import.
  # ignore_changes évite un replace destructif sur un volume existant.
  lifecycle {
    ignore_changes = [base_volume_name, base_volume_pool]
  }

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

  # vtnet0 — DMZ (OPNsense nano default : vtnet0=LAN → on surcharge via config.xml)
  network_interface {
    network_id     = var.dmz_network_id
    wait_for_lease = false
  }

  # vtnet1 — WAN (NAT libvirt, DHCP)
  # Config push via DMZ 192.168.1.1 → wait_for_lease inutile
  network_interface {
    network_id     = var.wan_network_id
    wait_for_lease = false
  }

  # vtnet2 — LAN (srv-db, srv-app)
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

# ── Push config.xml via SSH (DMZ) ────────────────────────────────────────────
# Pousse config.xml via l'IP DMZ d'OPNsense (192.168.1.1 par défaut).
# Le bridge DMZ de chaque instance a une IP hôte unique (dmz_host_ip) —
# on bind le SSH sur cette IP pour forcer le routage via le bon bridge.
# Avec golden image : SSH disponible immédiatement sans intervention manuelle.
# Sans golden image : bootstrap console requis (voir commentaire en tête).

resource "terraform_data" "opnsense_config_push" {
  triggers_replace = sha256(local.config_xml)

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      CFG="${local_sensitive_file.opnsense_config.filename}"
      BIND_IP="${var.dmz_host_ip}"
      OPNSENSE_IP="${local.dmz_ip}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5 -b $BIND_IP"

      # 1. Attendre SSH sur la DMZ (bind sur l'IP bridge de cette instance)
      echo "==> Attente SSH OPNsense DMZ ($OPNSENSE_IP via $BIND_IP)..."
      for i in $(seq 1 60); do
        if ssh $SSH_OPTS root@$OPNSENSE_IP true 2>/dev/null; then
          echo "==> SSH disponible (tentative $i)"
          break
        fi
        echo "  tentative $i/60, retry dans 10s..."
        sleep 10
      done

      if ! ssh $SSH_OPTS root@$OPNSENSE_IP true 2>/dev/null; then
        echo "ERREUR : OPNsense DMZ inaccessible ($OPNSENSE_IP)"
        echo "Sans golden image : bootstrap console requis :"
        echo "  virsh console → option 8 → shell"
        echo "  ssh-keygen -A"
        echo "  /usr/local/sbin/sshd -f /usr/local/etc/ssh/sshd_config"
        echo "  echo 'CLÉPUB' >> /root/.ssh/authorized_keys"
        exit 1
      fi

      # 2. Push config.xml
      echo "==> Push config.xml vers $OPNSENSE_IP..."
      scp $SSH_OPTS "$CFG" root@$OPNSENSE_IP:/conf/config.xml

      # 3. Reboot
      echo "==> Reboot OPNsense..."
      ssh $SSH_OPTS root@$OPNSENSE_IP "reboot" || true

      # 4. Attendre que OPNsense redémarre
      echo "==> Attente redémarrage OPNsense (DMZ $OPNSENSE_IP)..."
      sleep 30
      for i in $(seq 1 20); do
        if ssh $SSH_OPTS root@$OPNSENSE_IP true 2>/dev/null; then
          echo "==> OPNsense opérationnel (tentative $i)"
          break
        fi
        echo "  tentative $i/20, retry dans 15s..."
        sleep 15
      done

      echo "==> Config OPNsense appliquée."
    EOT
  }

  depends_on = [libvirt_domain.opnsense, local_sensitive_file.opnsense_config]
}
