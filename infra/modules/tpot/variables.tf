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

variable "dmz_network_id" {
  description = "ID libvirt du réseau DMZ"
  type        = string
}

variable "dmz_cidr" {
  description = "CIDR DMZ — T-Pot reçoit .50"
  type        = string
}

variable "ssh_public_key" {
  description = "Clé SSH publique autorisée pour l'accès management"
  type        = string
}

variable "vm_password_hash" {
  description = "Hash SHA512 mot de passe user breach — openssl passwd -6"
  type        = string
  sensitive   = true
}

variable "tpot_web_user" {
  description = "Utilisateur pour l'interface web T-Pot"
  type        = string
  default     = "admin"
}

variable "tpot_web_pw" {
  description = "Mot de passe interface web T-Pot (min 8 chars)"
  type        = string
  sensitive   = true
}

variable "vcpu" {
  type    = number
  default = 2
}

variable "memory_mb" {
  description = "RAM en MiB — T-Pot recommande 8192 minimum"
  type        = number
  default     = 8192
}

variable "disk_size" {
  description = "Taille disque en bytes"
  type        = number
  default     = 68719476736  # 64 GiB
}
