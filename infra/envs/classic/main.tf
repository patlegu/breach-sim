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

resource "libvirt_pool" "images" {
  name = var.libvirt_pool
  type = "dir"
  path = "/var/lib/libvirt/images"
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
  libvirt_pool       = libvirt_pool.images.name
  wan_network_id     = module.network.wan_network_id
  lan_network_id     = module.network.lan_network_id
  lan_cidr           = module.network.lan_cidr
  opnsense_image_url = var.opnsense_image_url
  image_cache_dir    = var.image_cache_dir
  root_password_hash = var.opnsense_root_hash
  ssh_public_key     = var.ssh_public_key
  api_key            = var.opnsense_api_key
  api_secret         = var.opnsense_api_secret
}

# ── VMs Linux (cloud-init) ────────────────────────────────────────────────────

module "classic_lab" {
  source = "../../modules/classic-lab"

  instance_id    = var.instance_id
  libvirt_uri    = var.libvirt_uri
  libvirt_pool   = libvirt_pool.images.name
  lan_network_id = module.network.lan_network_id
  lan_cidr       = module.network.lan_cidr
  ssh_public_key = var.ssh_public_key
  debian_image_url = var.debian_image_url
  image_cache_dir  = var.image_cache_dir
}
