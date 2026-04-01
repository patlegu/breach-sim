output "wan_network_id" {
  value = libvirt_network.wan.id
}

output "dmz_network_id" {
  value = libvirt_network.dmz.id
}

output "lan_network_id" {
  value = libvirt_network.lan.id
}

output "wan_cidr" {
  value = var.wan_cidr
}

output "dmz_cidr" {
  value = var.dmz_cidr
}

output "lan_cidr" {
  value = var.lan_cidr
}

output "dmz_gateway" {
  description = "IP gateway DMZ (OPNsense vtnet1)"
  value       = cidrhost(var.dmz_cidr, 1)
}

output "lan_gateway" {
  description = "IP gateway LAN (OPNsense vtnet2)"
  value       = cidrhost(var.lan_cidr, 1)
}
