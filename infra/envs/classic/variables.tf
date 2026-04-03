variable "instance_id" {
  description = "Numéro d'instance du lab (1, 2, …)"
  type        = number
  default     = 1
}

variable "libvirt_uri" {
  type    = string
  default = "qemu:///system"
}

variable "libvirt_pool" {
  type    = string
  default = "images"
}

# ── Images ────────────────────────────────────────────────────────────────────

variable "opnsense_image_url" {
  description = "URL image OPNsense nano amd64 (.img.bz2)"
  type        = string
  default     = "https://mirror.ams1.nl.leaseweb.net/opnsense/releases/25.1/OPNsense-25.1-nano-amd64.img.bz2"
}

variable "debian_image_url" {
  description = "URL image Debian cloud (qcow2)"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
}

variable "image_cache_dir" {
  type    = string
  default = "/var/lib/libvirt/images/.cache"
}

# ── Credentials ───────────────────────────────────────────────────────────────

variable "ssh_public_key" {
  description = "Clé SSH publique (injectée dans toutes les VMs)"
  type        = string
}

variable "opnsense_root_hash" {
  description = "Hash SHA512 mot de passe root OPNsense — openssl passwd -6 'monmotdepasse'"
  type        = string
  sensitive   = true
}

variable "vm_password_hash" {
  description = "Hash SHA512 mot de passe user breach (VMs Linux) — openssl passwd -6 'monmotdepasse'"
  type        = string
  sensitive   = true
}

variable "opnsense_api_key" {
  description = "Clé API OPNsense (80 chars alphanum) — openssl rand -hex 40"
  type        = string
  sensitive   = true
}

variable "opnsense_api_secret" {
  description = "Secret API OPNsense (80 chars alphanum) — openssl rand -hex 40"
  type        = string
  sensitive   = true
}

variable "tpot_web_user" {
  description = "Utilisateur interface web T-Pot"
  type        = string
  default     = "admin"
}

variable "tpot_web_pw" {
  description = "Mot de passe interface web T-Pot (min 8 chars)"
  type        = string
  sensitive   = true
}

variable "tpot_ports" {
  description = "Ports TCP honeypot T-Pot à exposer via OPNsense NAT"
  type        = list(number)
  default = [
    # SSH / Telnet (2222 réservé admin korrig)
    22, 23, 2323,
    # Mail
    25, 110, 143, 993, 995,
    # Web
    80, 8080, 8443,
    # FTP / Nameserver
    21, 42,
    # Windows / SMB / RDP
    135, 445, 1433, 3389,
    # VPN
    1723,
    # Industrial (Conpot)
    102, 502,
    # Databases
    3306, 5432, 6379, 27017,
    # VNC
    5900,
    # Android Debug Bridge (ADBHoney)
    5555,
    # SIP (Sentrypeer)
    5060, 5061,
    # Elasticsearch / log4pot
    9200,
    # Memcached TCP
    11211,
    # IPP (Ipphoney)
    631,
    # DICOM (Medpot)
    2575,
    # Misc
    8888,
  ]
}

variable "public_iface" {
  description = "Interface réseau publique de korrig (ex: enp41s0)"
  type        = string
  default     = "enp41s0"
}
