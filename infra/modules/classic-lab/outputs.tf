output "srv_web_ip" {
  value = cidrhost(var.dmz_cidr, 10)
}

output "srv_db_ip" {
  value = cidrhost(var.lan_cidr, 10)
}

output "srv_app_ip" {
  value = cidrhost(var.lan_cidr, 20)
}

output "vm_ips" {
  value = {
    for name, vm in local.vms : name => vm.ip
  }
}
