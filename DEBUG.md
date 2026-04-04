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

# Vérifier le DNAT SSH : le paquet part bien vers OPNsense WAN (virbr2, pas virbr3)
# Étape 1 — arrivée sur korrig
tcpdump -i enp41s0 -n tcp port 22
# Étape 2 — après DNAT, forwarding vers OPNsense WAN
tcpdump -i virbr2 -n tcp port 22
# Étape 3 — après pf rdr OPNsense, trafic OPNsense→T-Pot (src sera 192.168.1.1, pas l'attaquant)
# Sur OPNsense : tcpdump -i vtnet0 -n tcp port 22
# Sur korrig (bridge DMZ hôte) — montre le dernier saut OPNsense→T-Pot :
tcpdump -i virbr3 -n tcp port 22

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

### VMs

```bash
# Lister toutes les VMs (running + stopped)
virsh list --all

# Détail d'une VM (CPU, RAM, état)
virsh dominfo breach-1-opnsense

# Démarrer / arrêter / forcer l'arrêt
virsh start   breach-1-opnsense
virsh shutdown breach-1-opnsense
virsh destroy  breach-1-opnsense   # équivalent power off

# Console série (bootstrap sans SSH — quitter : Ctrl+])
virsh console breach-1-opnsense

# Snapshot rapide avant une opération risquée
virsh snapshot-create-as breach-1-opnsense snap-avant-modif
virsh snapshot-list breach-1-opnsense
virsh snapshot-revert breach-1-opnsense snap-avant-modif
```

### Interfaces réseau des VMs

```bash
# Interfaces et MACs d'une VM (XML complet)
virsh domiflist breach-1-opnsense

# Correspondance interface VM ↔ bridge hôte
# Exemple de sortie :
#  Interface   Type     Source   Model    MAC
#  vnet0       bridge   virbr2   virtio   52:54:00:xx  ← vtnet1 WAN  OPNsense
#  vnet1       bridge   virbr3   virtio   52:54:00:xx  ← vtnet0 DMZ  OPNsense
#  vnet2       bridge   virbr1   virtio   52:54:00:xx  ← vtnet2 LAN  OPNsense

# Statistiques trafic par interface virtuelle
virsh domifstat breach-1-opnsense vnet0

# Lister toutes les interfaces tap/vnet actives sur l'hôte
ip link show type tun
ip link show type bridge
```

### Réseaux libvirt

```bash
# Lister les réseaux (running + inactifs)
virsh net-list --all

# Détail d'un réseau (bridge, mode, DHCP)
virsh net-info breach-1-wan
virsh net-dumpxml breach-1-wan   # XML complet avec plage DHCP

# Baux DHCP actifs sur un réseau NAT
virsh net-dhcp-leases breach-1-wan

# IP voisines sur chaque bridge (VMs effectivement joignables)
ip neigh show dev virbr1    # LAN
ip neigh show dev virbr2    # WAN
ip neigh show dev virbr3    # DMZ
arp -n | grep virbr3
```

### Volumes / disques

```bash
# Lister les volumes dans le pool images
virsh vol-list images

# Taille réelle vs allouée d'un disque VM
virsh vol-info --pool images breach-1-opnsense.qcow2
qemu-img info /var/lib/libvirt/images/breach-1-opnsense.qcow2

# Capture d'un disque (VM à l'arrêt uniquement)
virsh shutdown breach-1-opnsense
virsh vol-download --pool images breach-1-opnsense.qcow2 /tmp/backup.qcow2
qemu-img convert -c -O qcow2 /tmp/backup.qcow2 /var/lib/libvirt/images/.cache/opnsense-golden.qcow2
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
