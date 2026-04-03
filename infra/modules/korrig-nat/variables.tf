variable "instance_id" {
  description = "Numéro d'instance du lab"
  type        = number
}

variable "wan_cidr" {
  description = "CIDR du réseau WAN libvirt (ex: 10.0.1.0/24)"
  type        = string
}

variable "opnsense_wan_ip" {
  description = "IP statique OPNsense sur le WAN (dérivée de wan_cidr .2)"
  type        = string
}

variable "libvirt_uri" {
  description = "URI libvirt (pour résoudre le nom du bridge WAN via virsh net-info)"
  type        = string
  default     = "qemu:///system"
}

variable "public_iface" {
  description = "Interface réseau publique de korrig (ex: enp41s0)"
  type        = string
  default     = "enp41s0"
}

variable "tpot_ports" {
  description = "Ports TCP à DNAT vers OPNsense WAN (honeypot ports)"
  type        = list(number)
  default     = [22, 23, 25, 80, 110, 143, 445, 1433, 3306, 3389, 5900, 6379, 8080, 8888, 27017]
}
