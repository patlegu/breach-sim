output "opnsense_wan_ip" {
  value = module.opnsense.wan_ip
}

output "opnsense_dmz_ip" {
  value = module.opnsense.dmz_ip
}

output "opnsense_lan_ip" {
  value = module.opnsense.lan_ip
}

output "tpot_ip" {
  value = module.tpot.tpot_ip
}

output "lab_summary" {
  value = <<-EOT
    Lab breach-sim #${var.instance_id}
    ──────────────────────────────────────────────────
    OPNsense WAN : ${module.opnsense.wan_ip}
    OPNsense DMZ : ${module.opnsense.dmz_ip}  (API: ${module.opnsense.api_base_url})
    OPNsense LAN : ${module.opnsense.lan_ip}

    DMZ (${module.network.dmz_cidr}) :
      tpot    : ${module.tpot.tpot_ip}
      srv-web : ${module.classic_lab.srv_web_ip}

    LAN (${module.network.lan_cidr}) :
      srv-db  : ${module.classic_lab.srv_db_ip}
      srv-app : ${module.classic_lab.srv_app_ip}
  EOT
}
