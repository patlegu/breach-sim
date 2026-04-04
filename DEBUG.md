# Debug — breach-sim

Aide-mémoire des commandes de diagnostic pour l'infra breach-sim sur `korrig.breizhland.eu`.

## Topologie réseau (rappel rapide)

```
Internet → enp41s0 (korrig) → virbr3 (DMZ 192.168.1.0/24)
                                ├── OPNsense vtnet0  192.168.1.1
                                └── T-Pot            192.168.1.50

                             → virbr1 (LAN 192.168.21.0/24)
                                ├── OPNsense vtnet2  192.168.21.1
                                ├── srv-db           192.168.21.10
                                └── srv-app          192.168.21.20

                             → virbr2 (WAN NAT 10.0.1.0/24)
                                └── OPNsense vtnet1  DHCP
```

---

## Accès SSH

```bash
# OPNsense (via bridge DMZ hôte)
ssh -o BindAddress=192.168.1.254 root@192.168.1.1

# T-Pot (port management)
ssh -p 64295 breach@192.168.1.50

# srv-web / srv-db / srv-app (via LAN)
ssh -o BindAddress=192.168.21.254 debian@192.168.21.10   # srv-db
ssh -o BindAddress=192.168.21.254 debian@192.168.21.20   # srv-app
```

---

## tcpdump — OPNsense (FreeBSD)

Connexion préalable : `ssh -o BindAddress=192.168.1.254 root@192.168.1.1`

```bash
# Tout le trafic TCP sur DMZ (vtnet0), sans résolution DNS
tcpdump -i vtnet0 -n tcp

# TCP hors adresses privées (trafic externe uniquement)
tcpdump -i vtnet0 -n tcp and not net 10.0.0.0/8 and not net 192.168.0.0/16 and not net 172.16.0.0/12

# Trafic entrant sur WAN (vtnet1)
tcpdump -i vtnet0 -n tcp

# Voir les connexions vers T-Pot depuis l'extérieur
tcpdump -i vtnet0 -n tcp and dst host 192.168.1.50

# Trafic LAN (vtnet2)
tcpdump -i vtnet2 -n

# SSH uniquement sur DMZ (port 22)
tcpdump -i vtnet0 -n tcp port 22

# Dump lisible avec horodatage (-tttt) et résumé (-q)
tcpdump -i vtnet0 -n -tttt -q tcp
```

---

## tcpdump — korrig (hôte Debian, interfaces physiques/bridges)

```bash
# Trafic entrant côté internet (interface physique)
tcpdump -i enp41s0 -n tcp

# Trafic entrant hors adresses locales (attaquants réels)
tcpdump -i enp41s0 -n tcp and not net 10.0.0.0/8 and not net 192.168.0.0/16 and not net 172.16.0.0/12

# Trafic sur le bridge DMZ (entre korrig et VMs)
tcpdump -i virbr3 -n

# Vérifier le DNAT SSH (port 22 korrig → T-Pot 192.168.1.50:22)
tcpdump -i enp41s0 -n tcp port 22
tcpdump -i virbr3 -n tcp port 22 and host 192.168.1.50

# IP sources qui frappent le port 22 (top attaquants)
tcpdump -i enp41s0 -n tcp port 22 -c 200 | awk '{print $3}' | cut -d. -f1-4 | sort | uniq -c | sort -rn | head -20
```

---

## iptables — vérifier le DNAT / FORWARD

Architecture : tout le trafic honeypot transite par OPNsense (virbr2), pas de chemin direct vers T-Pot.
```
internet → enp41s0 → DNAT korrig → OPNsense WAN (10.0.1.2, virbr2) → pf rdr OPNsense → T-Pot (192.168.1.50)
```

```bash
# Règles NAT actives
iptables -t nat -L -n -v --line-numbers

# Règles FORWARD — 33 règles honeypot (enp41s0 → virbr2) + chains libvirt
iptables -L FORWARD -n -v --line-numbers

# Vérifier le DNAT SSH (doit pointer vers 10.0.1.2, pas 192.168.1.50)
iptables -t nat -L PREROUTING -n -v | grep "dpt:22"

# Compteurs de paquets sur tous les DNATs honeypot
iptables -t nat -L PREROUTING -n -v | grep virbr2

# Relire les règles persistantes
netfilter-persistent reload
```

---

## T-Pot — état des containers

```bash
# Via SSH (port 64295)
ssh -p 64295 breach@192.168.1.50

# Containers up/down
sudo docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Containers en erreur ou en restart loop
sudo docker ps --filter "status=restarting" --filter "status=exited"

# Logs d'un container (ex: cowrie)
sudo docker logs cowrie --tail 50 -f

# IPs qui ont tenté de se connecter via Cowrie (SSH honeypot)
sudo docker logs cowrie 2>&1 | grep "New connection" | awk '{print $7}' | sort | uniq -c | sort -rn | head -20

# Interface web T-Pot
# https://192.168.1.50:64297  (depuis korrig ou avec tunnel SSH)
```

---

## T-Pot — IPs attaquantes

```bash
# Top IPs brutes sur Cowrie (SSH)
sudo docker logs cowrie 2>&1 | grep "login attempt" | grep -oP '\d+\.\d+\.\d+\.\d+' | sort | uniq -c | sort -rn | head -30

# Top IPs sur dionaea (malware / multi-protocoles)
sudo docker logs dionaea 2>&1 | grep -oP '\d+\.\d+\.\d+\.\d+' | sort | uniq -c | sort -rn | head -20

# Depuis korrig : IPs qui frappent en direct (avant DNAT)
tcpdump -i enp41s0 -n tcp port 22 -c 500 | grep -oP '\d+\.\d+\.\d+\.\d+' | sort | uniq -c | sort -rn | head -20
```

---

## Libvirt / VMs

```bash
# État des VMs (sur korrig)
virsh list --all

# Console OPNsense (bootstrap sans SSH)
virsh console breach-1-opnsense
# Quitter : Ctrl+]

# Vérifier les bridges réseau
virsh net-list --all
virsh net-info virbr3

# IP assignées sur le bridge DMZ
arp -n | grep virbr3
ip neigh show dev virbr3
```

---

## OPNsense — sanity checks

```bash
# Connexion
ssh -o BindAddress=192.168.1.254 root@192.168.1.1

# Interfaces assignées
ifconfig -a | grep -E "^(vtnet|flags)"

# Table de routage
netstat -rn

# Firewall logs (pflog)
tcpdump -i pflog0 -n

# Firewall logs filtrés sur T-Pot
tcpdump -i pflog0 -n host 192.168.1.50

# Redémarrer le SSH si tombé
/usr/local/sbin/sshd -f /usr/local/etc/ssh/sshd_config
```

---

## Tunnel SSH pour accéder aux UIs web depuis la machine locale

```bash
# T-Pot UI (port 64297) accessible sur localhost:8443
ssh -L 8443:192.168.1.50:64297 -o BindAddress=192.168.1.254 root@192.168.1.1 -N

# OPNsense WebUI (port 443) accessible sur localhost:8444
ssh -L 8444:192.168.1.1:443 -o BindAddress=192.168.1.254 root@192.168.1.1 -N
```
