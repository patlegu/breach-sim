output "wan_ip" {
  description = "IP WAN obtenue par DHCP (disponible après premier boot)"
  value       = libvirt_domain.opnsense.network_interface[0].addresses[0]
}

output "lan_ip" {
  description = "IP LAN statique OPNsense (gateway du lab)"
  value       = cidrhost(var.lan_cidr, 1)
}

output "api_base_url" {
  description = "URL de base de l'API REST OPNsense"
  value       = "https://${cidrhost(var.lan_cidr, 1)}/api"
}

output "domain_name" {
  value = libvirt_domain.opnsense.name
}
