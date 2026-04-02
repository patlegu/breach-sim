output "wan_ip" {
  description = "IP WAN obtenue par DHCP (disponible après premier boot)"
  value       = try(libvirt_domain.opnsense.network_interface[1].addresses[0], "dhcp-pending")
}

output "dmz_ip" {
  description = "IP DMZ statique OPNsense (gateway DMZ)"
  value       = local.dmz_ip
}

output "lan_ip" {
  description = "IP LAN statique OPNsense (gateway LAN)"
  value       = local.lan_ip
}

output "api_base_url" {
  description = "URL de base de l'API REST OPNsense"
  value       = "https://${local.dmz_ip}/api"
}

output "domain_name" {
  value = libvirt_domain.opnsense.name
}
