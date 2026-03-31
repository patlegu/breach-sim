output "cp_ip" {
  value = cidrhost(var.lan_cidr, 30)
}

output "worker_ips" {
  value = {
    worker1 = cidrhost(var.lan_cidr, 31)
    worker2 = cidrhost(var.lan_cidr, 32)
  }
}

output "k3s_token" {
  value     = random_password.k3s_token.result
  sensitive = true
}

output "kubeconfig_cmd" {
  description = "Commande pour récupérer le kubeconfig depuis le CP"
  value       = "ssh breach@${cidrhost(var.lan_cidr, 30)} 'sudo cat /etc/rancher/k3s/k3s.yaml' | sed 's/127.0.0.1/${cidrhost(var.lan_cidr, 30)}/g'"
}
