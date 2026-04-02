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
    dmz_ip        = local.dmz_ip
    dmz_prefix    = local.dmz_prefix
    dmz_dhcp_from = local.dmz_dhcp_from
    dmz_dhcp_to   = local.dmz_dhcp_to
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

  # vtnet0 — DMZ (OPNsense nano default : vtnet0=LAN → on surcharge via config.xml)
  network_interface {
    network_id     = var.dmz_network_id
    wait_for_lease = false
  }

  # vtnet1 — WAN (OPNsense nano default : vtnet1=WAN → correspond au NAT libvirt)
  # OPNsense obtient une IP DHCP ici dès le premier boot → accessible pour config push
  network_interface {
    network_id     = var.wan_network_id
    wait_for_lease = true
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
      SSH_OPTS="-o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5"
      VIRSH="virsh -c ${var.libvirt_uri}"

      # 1. Trouver l'IP WAN d'OPNsense via les leases DHCP du réseau WAN libvirt.
      #    virsh domifaddr affiche les noms tap hôte (vnet0/vnet1), pas les noms
      #    guest (vtnet0/vtnet1) → on interroge directement le réseau NAT.
      echo "==> Recherche IP WAN OPNsense..."
      WAN_IP=""
      for i in $(seq 1 60); do
        WAN_IP=$($VIRSH net-dhcp-leases breach-${var.instance_id}-wan 2>/dev/null \
          | awk 'NR>2 && $5 != "" {gsub(/\/.*/, "", $5); print $5}' | head -1)
        if [ -n "$WAN_IP" ]; then
          echo "==> IP WAN trouvée : $WAN_IP (tentative $i)"
          break
        fi
        echo "  attente IP DHCP WAN... tentative $i/60"
        sleep 10
      done

      # Fallback sur DMZ si WAN inaccessible (OPNsense déjà configuré)
      if [ -z "$WAN_IP" ]; then
        WAN_IP="${local.dmz_ip}"
        echo "==> Fallback sur IP DMZ : $WAN_IP"
      fi

      # 2. Attendre que SSH soit disponible
      echo "==> Attente SSH OPNsense ($WAN_IP)..."
      for i in $(seq 1 30); do
        if ssh $SSH_OPTS root@$WAN_IP true 2>/dev/null; then
          echo "==> SSH disponible (tentative $i)"
          break
        fi
        echo "  tentative $i/30, retry dans 10s..."
        sleep 10
      done

      if ! ssh $SSH_OPTS root@$WAN_IP true 2>/dev/null; then
        echo "ERREUR : OPNsense inaccessible via SSH ($WAN_IP)"
        echo "Bootstrap : activer SSH via console (menu 14) + ajouter clé SSH"
        exit 1
      fi

      # 3. Push config.xml
      echo "==> Push config.xml vers $WAN_IP..."
      scp $SSH_OPTS "$CFG" root@$WAN_IP:/conf/config.xml

      # 4. Activer serial console pour virsh, puis reboot pour appliquer
      #    les nouveaux assignments d'interfaces
      echo "==> Activation console série + reboot..."
      ssh $SSH_OPTS root@$WAN_IP \
        "printf 'boot_multicons=\"YES\"\nboot_serial=\"YES\"\ncomconsole_speed=\"115200\"\nconsole=\"comconsole,vidconsole\"\n' >> /boot/loader.conf.local
         # Script rc.d pour fixer ttyu0 à chaque boot (OPNsense réinitialise /etc/ttys)
         cat > /usr/local/etc/rc.d/serial_console << 'RCEOF'
#!/bin/sh
# PROVIDE: serial_console
# REQUIRE: LOGIN
# KEYWORD: nojail
. /etc/rc.subr
name=serial_console
start_cmd=serial_console_start
serial_console_start() {
  sed -i '' 's/ttyu0.*off secure/ttyu0   \"\/usr\/libexec\/getty al.3wire.115200\"    vt100   onifconsole secure/' /etc/ttys
  kill -HUP 1
}
load_rc_config \$name
run_rc_command \"\$1\"
RCEOF
         chmod 555 /usr/local/etc/rc.d/serial_console
         /usr/local/etc/rc.d/serial_console start
         reboot" || true

      # 5. Attendre que OPNsense redémarre et soit joignable sur DMZ
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

      echo "==> Config OPNsense appliquée et interfaces reconfigurées."
    EOT
  }

  depends_on = [libvirt_domain.opnsense, local_sensitive_file.opnsense_config]
}
