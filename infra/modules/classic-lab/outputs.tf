output "srv_web_ip" {
  value = cidrhost(var.lan_cidr, 10)
}

output "srv_db_ip" {
  value = cidrhost(var.lan_cidr, 20)
}

output "infected_ip" {
  value = cidrhost(var.lan_cidr, 15)
}

output "vm_ips" {
  value = {
    for name, vm in libvirt_domain.vm :
    name => vm.network_interface[0].addresses[0]
  }
}
