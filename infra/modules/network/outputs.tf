output "wan_network_id" {
  description = "ID libvirt du réseau WAN"
  value       = libvirt_network.wan.id
}

output "lan_network_id" {
  description = "ID libvirt du réseau LAN"
  value       = libvirt_network.lan.id
}

output "wan_cidr" {
  value = var.wan_cidr
}

output "lan_cidr" {
  value = var.lan_cidr
}

output "lan_gateway" {
  description = "IP du gateway LAN (OPNsense em1, première IP utilisable)"
  value       = cidrhost(var.lan_cidr, 1)
}
