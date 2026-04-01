output "tpot_ip" {
  description = "IP statique T-Pot dans la DMZ"
  value       = local.tpot_ip
}

output "tpot_domain_id" {
  description = "ID du domaine libvirt T-Pot"
  value       = libvirt_domain.tpot.id
}
