variable "libvirt_uri" {
  type    = string
  default = "qemu:///system"
}

variable "instance_id" {
  description = "Identifiant unique du lab (1, 2, …). Différencie les bridges et subnets."
  type        = number
}

variable "wan_cidr" {
  description = "CIDR du réseau WAN (NAT). Doit être unique par instance."
  type        = string
  # ex : "10.0.1.0/24" pour instance 1, "10.0.2.0/24" pour instance 2
}

variable "dmz_cidr" {
  description = "CIDR du réseau DMZ (isolé, exposé à internet via OPNsense)."
  type        = string
  # ex : "192.168.11.0/24" pour instance 1, "192.168.21.0/24" pour instance 2
}

variable "lan_cidr" {
  description = "CIDR du réseau LAN (isolé, non accessible depuis internet)."
  type        = string
  # ex : "192.168.12.0/24" pour instance 1, "192.168.22.0/24" pour instance 2
}
