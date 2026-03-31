output "opnsense_wan_ip" {
  value = module.opnsense.wan_ip
}

output "opnsense_lan_ip" {
  value = module.opnsense.lan_ip
}

output "opnsense_api_url" {
  value = module.opnsense.api_base_url
}

output "srv_web_ip" {
  value = module.classic_lab.srv_web_ip
}

output "srv_db_ip" {
  value = module.classic_lab.srv_db_ip
}

output "infected_ip" {
  value = module.classic_lab.infected_ip
}

output "lab_summary" {
  value = <<-EOT
    Lab breach-sim #${var.instance_id}
    ──────────────────────────────────
    OPNsense WAN : ${module.opnsense.wan_ip}
    OPNsense LAN : ${module.opnsense.lan_ip}  (API: ${module.opnsense.api_base_url})
    srv-web      : ${module.classic_lab.srv_web_ip}
    srv-db       : ${module.classic_lab.srv_db_ip}
    infected     : ${module.classic_lab.infected_ip}
  EOT
}
