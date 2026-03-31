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
  type = string
}

variable "lan_cidr" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "debian_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "image_cache_dir" {
  type    = string
  default = "/var/lib/libvirt/images/.cache"
}

# ── Ressources CP ─────────────────────────────────────────────────────────────

variable "cp_vcpu" {
  type    = number
  default = 2
}

variable "cp_memory" {
  description = "RAM CP en MiB"
  type        = number
  default     = 2048
}

variable "cp_disk_size" {
  type    = number
  default = 21474836480   # 20 GiB
}

# ── Ressources workers ────────────────────────────────────────────────────────

variable "worker_disk_size" {
  type    = number
  default = 21474836480   # 20 GiB
}
