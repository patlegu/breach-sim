variable "instance_id" {
  type    = number
  default = 1
}

variable "libvirt_uri" {
  type    = string
  default = "qemu:///system"
}

variable "libvirt_pool" {
  type    = string
  default = "images"
}

variable "opnsense_image_url" {
  type    = string
  default = "https://mirror.ams1.nl.leaseweb.net/opnsense/releases/25.1/OPNsense-25.1-nano-amd64.img.bz2"
}

variable "debian_image_url" {
  type    = string
  default = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "image_cache_dir" {
  type    = string
  default = "/var/lib/libvirt/images/.cache"
}

variable "ssh_public_key" {
  type = string
}

variable "opnsense_root_hash" {
  type      = string
  sensitive = true
}

variable "opnsense_api_key" {
  type      = string
  sensitive = true
}

variable "opnsense_api_secret" {
  type      = string
  sensitive = true
}
