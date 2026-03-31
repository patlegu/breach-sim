variable "instance_id" {
  type = number
}

variable "libvirt_uri" {
  type    = string
  default = "qemu:///system"
}

variable "libvirt_pool" {
  type    = string
  default = "images"
}

variable "lan_network_id" {
  description = "ID libvirt du réseau LAN (depuis module/network)"
  type        = string
}

variable "lan_cidr" {
  description = "CIDR LAN — calcul des IPs statiques"
  type        = string
}

variable "ssh_public_key" {
  description = "Clé SSH publique injectée dans toutes les VMs"
  type        = string
}

variable "vm_password_hash" {
  description = "Hash SHA512 mot de passe user breach — openssl passwd -6 'monmotdepasse'"
  type        = string
  sensitive   = true
}

variable "debian_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "image_cache_dir" {
  type    = string
  default = "/var/lib/libvirt/images/.cache"
}
