variable "instance_id" {
  description = "Identifiant unique du lab"
  type        = number
}

variable "libvirt_uri" {
  type    = string
  default = "qemu:///system"
}

variable "libvirt_pool" {
  type    = string
  default = "images"
}

variable "wan_network_id" {
  description = "ID libvirt du réseau WAN"
  type        = string
}

variable "dmz_network_id" {
  description = "ID libvirt du réseau DMZ (vtnet1 OPNsense)"
  type        = string
}

variable "lan_network_id" {
  description = "ID libvirt du réseau LAN (vtnet2 OPNsense)"
  type        = string
}

variable "dmz_cidr" {
  description = "CIDR DMZ — IP statique OPNsense (.1), DHCP honeypots/web"
  type        = string
}

variable "lan_cidr" {
  description = "CIDR LAN — IP statique OPNsense (.1), DHCP db/app"
  type        = string
}

# ── Image ─────────────────────────────────────────────────────────────────────

variable "opnsense_image_url" {
  description = "URL de l'image OPNsense nano (bz2). Ex: miroir officiel OPNsense."
  type        = string
  # https://mirror.ams1.nl.leaseweb.net/opnsense/releases/25.1/OPNsense-25.1-nano-amd64.img.bz2
}

variable "image_cache_dir" {
  description = "Répertoire local pour cacher les images téléchargées"
  type        = string
  default     = "/var/lib/libvirt/images/.cache"
}

# ── VM ────────────────────────────────────────────────────────────────────────

variable "vcpu" {
  type    = number
  default = 2
}

variable "memory_mb" {
  description = "RAM en MiB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Taille disque en bytes (CoW depuis base)"
  type        = number
  default     = 10737418240  # 10 GiB
}

# ── Credentials initiaux ──────────────────────────────────────────────────────

variable "root_password_hash" {
  description = "Hash SHA512 du mot de passe root OPNsense (openssl passwd -6)"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "Clé SSH publique autorisée pour root"
  type        = string
}

variable "api_key" {
  description = "Clé API REST OPNsense (alphanum, 80 chars)"
  type        = string
  sensitive   = true
}

variable "api_secret" {
  description = "Secret API REST OPNsense (alphanum, 80 chars)"
  type        = string
  sensitive   = true
}
