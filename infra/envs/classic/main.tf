terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# ── Pool de stockage libvirt ──────────────────────────────────────────────────
# Utilise virsh directement (idempotent) pour éviter les destructions de pool
# qui échouent quand le répertoire est non-vide (images de base en cache).

resource "terraform_data" "libvirt_pool" {
  input = "${var.libvirt_uri}|${var.libvirt_pool}"

  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      VIRSH="virsh -c ${var.libvirt_uri}"
      POOL="${var.libvirt_pool}"
      # Créer le pool s'il n'existe pas encore
      if ! $VIRSH pool-info "$POOL" >/dev/null 2>&1; then
        echo "==> Définition du pool libvirt '$POOL'..."
        $VIRSH pool-define-as "$POOL" dir --target /var/lib/libvirt/images
        $VIRSH pool-autostart "$POOL"
      fi
      # Démarrer le pool s'il n'est pas actif (pool-start idempotent via || true)
      if ! $VIRSH pool-info "$POOL" | grep -q "State:.*running"; then
        echo "==> Démarrage du pool '$POOL'..."
        $VIRSH pool-start "$POOL"
      fi
      echo "==> Pool '$POOL' actif."
    EOT
  }
}

# ── Réseau ────────────────────────────────────────────────────────────────────

module "network" {
  source = "../../modules/network"

  instance_id = var.instance_id
  wan_cidr    = "10.0.${var.instance_id}.0/24"
  lan_cidr    = "192.168.${10 + var.instance_id}.0/24"
}

# ── OPNsense ──────────────────────────────────────────────────────────────────

module "opnsense" {
  source = "../../modules/opnsense"

  instance_id        = var.instance_id
  libvirt_uri        = var.libvirt_uri
  libvirt_pool       = var.libvirt_pool
  wan_network_id     = module.network.wan_network_id
  lan_network_id     = module.network.lan_network_id
  lan_cidr           = module.network.lan_cidr
  opnsense_image_url = var.opnsense_image_url
  image_cache_dir    = var.image_cache_dir
  root_password_hash = var.opnsense_root_hash
  ssh_public_key     = var.ssh_public_key
  api_key            = var.opnsense_api_key
  api_secret         = var.opnsense_api_secret

  depends_on = [terraform_data.libvirt_pool]
}

# ── VMs Linux (cloud-init) ────────────────────────────────────────────────────

module "classic_lab" {
  source = "../../modules/classic-lab"

  instance_id    = var.instance_id
  libvirt_uri    = var.libvirt_uri
  libvirt_pool   = var.libvirt_pool
  lan_network_id = module.network.lan_network_id
  lan_cidr       = module.network.lan_cidr
  ssh_public_key = var.ssh_public_key
  debian_image_url = var.debian_image_url
  image_cache_dir  = var.image_cache_dir

  depends_on = [terraform_data.libvirt_pool]
}
