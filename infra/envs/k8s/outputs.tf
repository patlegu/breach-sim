output "opnsense_api_url" {
  value = module.opnsense.api_base_url
}

output "k3s_cp_ip" {
  value = module.k8s_lab.cp_ip
}

output "k3s_worker_ips" {
  value = module.k8s_lab.worker_ips
}

output "kubeconfig_cmd" {
  value = module.k8s_lab.kubeconfig_cmd
}

output "lab_summary" {
  value = <<-EOT
    Lab breach-sim k8s #${var.instance_id}
    ──────────────────────────────────────
    OPNsense WAN : ${module.opnsense.wan_ip}
    OPNsense LAN : ${module.opnsense.lan_ip}  (API: ${module.opnsense.api_base_url})
    k3s CP       : ${module.k8s_lab.cp_ip}
    k3s worker1  : ${module.k8s_lab.worker_ips.worker1}
    k3s worker2  : ${module.k8s_lab.worker_ips.worker2}

    Kubeconfig   : ${module.k8s_lab.kubeconfig_cmd}
  EOT
}
