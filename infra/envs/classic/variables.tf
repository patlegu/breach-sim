variable "instance_id" {
  description = "Numéro d'instance du lab (1, 2, …)"
  type        = number
  default     = 1
}

variable "libvirt_uri" {
  type    = string
  default = "qemu:///system"
}

variable "libvirt_pool" {
  type    = string
  default = "images"
}

# ── Images ────────────────────────────────────────────────────────────────────

variable "debian_image_url" {
  description = "URL image Debian cloud (qcow2)"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "image_cache_dir" {
  type    = string
  default = "/var/lib/libvirt/images/.cache"
}

# ── Credentials ───────────────────────────────────────────────────────────────

variable "ssh_public_key" {
  description = "Clé SSH publique (injectée dans toutes les VMs)"
  type        = string
}

variable "opnsense_root_hash" {
  description = "Hash SHA512 mot de passe root OPNsense — openssl passwd -6 'monmotdepasse'"
  type        = string
  sensitive   = true
}

variable "vm_password_hash" {
  description = "Hash SHA512 mot de passe user breach (VMs Linux) — openssl passwd -6 'monmotdepasse'"
  type        = string
  sensitive   = true
}

variable "opnsense_api_key" {
  description = "Clé API OPNsense (80 chars alphanum) — openssl rand -hex 40"
  type        = string
  sensitive   = true
}

variable "opnsense_api_secret" {
  description = "Secret API OPNsense (80 chars alphanum) — openssl rand -hex 40"
  type        = string
  sensitive   = true
}

variable "tpot_web_user" {
  description = "Utilisateur interface web T-Pot"
  type        = string
  default     = "admin"
}

variable "tpot_web_pw" {
  description = "Mot de passe interface web T-Pot (min 8 chars)"
  type        = string
  sensitive   = true
}
