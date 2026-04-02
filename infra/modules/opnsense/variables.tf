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
# Golden image : opnsense-golden.qcow2 dans image_cache_dir.
# Créée une fois depuis une instance OPNsense bootstrapée :
#   virsh vol-download --pool images breach-1-opnsense.qcow2 /tmp/cow.qcow2
#   qemu-img convert -c -O qcow2 /tmp/cow.qcow2 <image_cache_dir>/opnsense-golden.qcow2

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
