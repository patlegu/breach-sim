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
#   Le golden image (opnsense-golden.qcow2) démarre avec SSH activé et la
#   clé SSH autorisée → aucune intervention console requise.
#   Créer le golden depuis l'instance de référence (une seule fois) :
#     virsh vol-download --pool images breach-1-opnsense.qcow2 /tmp/cow.qcow2
#     qemu-img convert -c -O qcow2 /tmp/cow.qcow2 <cache_dir>/opnsense-golden.qcow2

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
# L'image nano/vga OPNsense est téléchargée une seule fois dans le pool libvirt.
# On crée ensuite un volume par instance (copy-on-write depuis la base).

resource "terraform_data" "opnsense_base" {
  input = "${var.image_cache_dir}/opnsense-golden.qcow2"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      GOLDEN="${var.image_cache_dir}/opnsense-golden.qcow2"
      if [ ! -f "$GOLDEN" ]; then
        echo "ERREUR : golden image OPNsense introuvable : $GOLDEN"
        echo ""
        echo "Créer depuis l'instance de référence :"
        echo "  virsh vol-download --pool ${var.libvirt_pool} breach-1-opnsense.qcow2 /tmp/opnsense-cow.qcow2"
        echo "  qemu-img convert -c -O qcow2 /tmp/opnsense-cow.qcow2 $GOLDEN"
        echo "  rm /tmp/opnsense-cow.qcow2"
        exit 1
      fi
      echo "==> Golden image OPNsense : $GOLDEN ($(qemu-img info --output json "$GOLDEN" | grep '"virtual-size"' | grep -oP '\d+' | head -1 | awk '{printf "%.1f GiB", $1/1073741824}'))"
    EOT
  }
}

resource "terraform_data" "opnsense_base_volume" {
  input = "${var.libvirt_uri}|${var.libvirt_pool}|${var.image_cache_dir}"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      VIRSH="virsh -c ${var.libvirt_uri}"
      BASE="opnsense-golden.qcow2"
      if ! $VIRSH vol-info --pool ${var.libvirt_pool} "$BASE" >/dev/null 2>&1; then
        echo "==> Upload golden image dans le pool libvirt..."
        $VIRSH vol-create-as ${var.libvirt_pool} "$BASE" 10G --format qcow2
        $VIRSH vol-upload --pool ${var.libvirt_pool} "$BASE" "${var.image_cache_dir}/opnsense-golden.qcow2"
        echo "==> Golden image uploadée."
      else
        echo "==> Golden image déjà présente dans le pool."
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      URI=$(echo "${self.input}" | cut -d'|' -f1)
      POOL=$(echo "${self.input}" | cut -d'|' -f2)
      virsh -c "$URI" vol-delete --pool "$POOL" opnsense-golden.qcow2 2>/dev/null || true
    EOT
  }

  depends_on = [terraform_data.opnsense_base]
}

# ── Volume disque OPNsense (CoW depuis la base) ───────────────────────────────

resource "libvirt_volume" "opnsense" {
  name             = "${local.name}.qcow2"
  pool             = var.libvirt_pool
  base_volume_name = "opnsense-golden.qcow2"
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
      CFG="${local_sensitive_file.opnsense_config.filename}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=5"

      # OPNsense serial image démarre avec vtnet0=LAN=192.168.1.1 par défaut.
      # Notre bridge DMZ (libvirt mode=none) est sur le même réseau → accessible
      # directement depuis korrig sans pfctl -d ni chasse à l'IP WAN.
      # Bootstrap (premier déploiement uniquement) :
      #   1. virsh console → menu 8 (Shell)
      #   2. ssh-keygen -A && /usr/local/sbin/sshd -f /usr/local/etc/ssh/sshd_config
      #   3. echo "CLÉPUB" >> /root/.ssh/authorized_keys
      OPNSENSE_IP="192.168.1.1"

      # 1. Attendre que SSH soit disponible sur le LAN défaut OPNsense
      echo "==> Attente SSH OPNsense ($OPNSENSE_IP)..."
      for i in $(seq 1 60); do
        if ssh $SSH_OPTS root@$OPNSENSE_IP true 2>/dev/null; then
          echo "==> SSH disponible (tentative $i)"
          break
        fi
        echo "  tentative $i/60, retry dans 10s..."
        sleep 10
      done

      if ! ssh $SSH_OPTS root@$OPNSENSE_IP true 2>/dev/null; then
        echo "ERREUR : OPNsense inaccessible via SSH ($OPNSENSE_IP)"
        echo "Bootstrap : activer SSH via console (option 8 du menu)"
        echo "  ssh-keygen -A"
        echo "  /usr/local/sbin/sshd -f /usr/local/etc/ssh/sshd_config"
        echo "  echo 'CLÉPUB' >> /root/.ssh/authorized_keys"
        exit 1
      fi

      # 2. Push config.xml
      echo "==> Push config.xml vers $OPNSENSE_IP..."
      scp $SSH_OPTS "$CFG" root@$OPNSENSE_IP:/conf/config.xml

      # 3. Reboot pour appliquer la configuration complète
      echo "==> Reboot pour appliquer la configuration..."
      ssh $SSH_OPTS root@$OPNSENSE_IP "reboot" || true

      # 4. Attendre que OPNsense redémarre et soit joignable sur DMZ
      echo "==> Attente redémarrage OPNsense (DMZ ${local.dmz_ip})..."
      sleep 30
      for i in $(seq 1 20); do
        if ssh $SSH_OPTS root@${local.dmz_ip} true 2>/dev/null; then
          echo "==> OPNsense opérationnel sur DMZ (tentative $i)"
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
