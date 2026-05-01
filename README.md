# TP2 AWS — Infrastructure Cloud Hybride Haute Disponibilité avec VPN Pritunl et Odoo
## Keyce Informatique — B3 Réseaux & Sécurité Informatique
## Auteur : Nell Mvele

---

## 📋 Table des matières

1. [Présentation](#présentation)
2. [Architecture globale](#architecture-globale)
3. [Prérequis](#prérequis)
4. [TP1 — Infrastructure HA avec VPN Pritunl](#tp1--infrastructure-ha-avec-vpn-pritunl)
5. [TP2 — Déploiement Applicatif Odoo en HA](#tp2--déploiement-applicatif-odoo-en-ha)
6. [Haute Disponibilité Base de Données — Patroni](#haute-disponibilité-base-de-données--patroni)
7. [Haute Disponibilité Filestore — lsyncd](#haute-disponibilité-filestore--lsyncd)
8. [Load Balancer Odoo HA](#load-balancer-odoo-ha)
9. [Test de résilience](#test-de-résilience)
10. [Nettoyage des ressources](#nettoyage-des-ressources)
11. [Dépannage](#dépannage)

---

## Présentation

Ce projet déploie une infrastructure cloud AWS **hybride** complète en deux étapes :

- **TP1** : Architecture Haute Disponibilité avec VPN Pritunl sur AWS.
  - VPC multi-AZ, Auto Scaling Group, Application Load Balancer, S3 + Lambda.
  - Déployé via **Terraform** (Infrastructure as Code).

- **TP2** : Déploiement applicatif Odoo 17 en mode HA cloud-local.
  - Hybridation réseau local ↔ AWS via VPN Pritunl (OpenVPN).
  - Odoo 17 conteneurisé avec Docker sur 2 instances EC2.
  - **PostgreSQL 15 + Patroni** : réplication synchrone avec failover automatique.
  - **EFS partagé** : filestore commun aux deux instances Odoo.
  - **lsyncd bidirectionnel** : réplication du filestore en temps réel.
  - **ALB Odoo HA** : point d'entrée unique avec répartition de charge.

> **Pourquoi cloud-local ?**
> L'architecture utilise des outils open-source self-managed (Patroni, etcd, lsyncd) sur des instances EC2, sans dépendre de services managés AWS comme RDS. N'importe quelle entreprise peut reproduire la même architecture sur ses propres serveurs physiques.

---

## Architecture globale

```
Réseau Local (Debian)
    │
    │ VPN OpenVPN (Pritunl) — UDP :1194
    │
Internet
    │
    ├── HTTP :80 ──► ALB Odoo HA (alb-odoo-ha)
    │                        │
    │              ┌─────────┴─────────┐
    │         AZ us-east-1a      AZ us-east-1b
    │    EC2 — Instance 2     EC2 — Instance 1
    │    3.211.244.215         54.235.144.196
    │    10.0.1.11             10.0.2.40
    │    Pritunl VPN           Odoo 17 Docker
    │    Odoo 17 Docker        Patroni PRIMARY
    │    Patroni STANDBY       etcd (arbitre)
    │              │                   │
    │              └────── EFS ────────┘
    │               /mnt/efs/odoo-filestore
    │                        │
    │              ┌─────────┴─────────┐
    │         lsyncd →           ← lsyncd
    │    EFS Backup Inst.2   EFS Backup Inst.1
    │
    ├── Patroni PRIMARY (10.0.2.40:5432)
    │         │ Réplication Synchrone (Lag=0)
    │   Patroni STANDBY (10.0.1.11:5432)
    │         │ Failover automatique via etcd
    │
    ├── S3 Bucket + Lambda Python
    └── CloudWatch (monitoring CPU)
```

---

## Prérequis

### Outils à installer

#### 1. AWS CLI
Télécharger : https://aws.amazon.com/fr/cli/
```bash
aws --version
```

#### 2. Terraform (>= 1.5)
Télécharger : https://developer.hashicorp.com/terraform/downloads
```bash
terraform version
```

#### 3. Configurer AWS CLI
```bash
aws configure
# AWS Access Key ID     : votre_access_key
# AWS Secret Access Key : votre_secret_key
# Default region name   : us-east-1
# Default output format : json

# Vérifier :
aws sts get-caller-identity
```

#### 4. Docker (pour TP2)
Télécharger : https://www.docker.com/products/docker-desktop/
```bash
docker --version
```

#### 5. Client OpenVPN (pour TP2)
- **Windows/Mac** : https://openvpn.net/client/
- **Linux/Debian** :
```bash
sudo apt install openvpn -y
```

---

## TP1 — Infrastructure HA avec VPN Pritunl

### Ce qui est déployé
- **VPC** 10.0.0.0/16 multi-AZ (2 subnets publics + 2 privés)
- **2 NAT Gateways** (un par AZ)
- **Application Load Balancer** avec SSL (ALB Pritunl)
- **Auto Scaling Group** : min 2, max 4 instances EC2 t3.small
- **Pritunl VPN** sur chaque instance (OpenVPN)
- **S3 Bucket** (versionné, chiffré AES256)
- **Lambda Python 3.12** (traitement automatique des logs)
- **CloudWatch** (alertes CPU scale-up/down)

### Structure des fichiers Terraform

```
tp1/
├── main.tf            # VPC, subnets, NAT Gateways, routes
├── ec2_asg.tf         # Launch Template, ALB, ASG, CloudWatch
├── s3_lambda.tf       # Bucket S3 + fonction Lambda
├── security_groups.tf # Règles de sécurité réseau
├── variables.tf       # Variables configurables
├── versions.tf        # Providers Terraform
└── outputs.tf         # Valeurs exportées après déploiement
```

### Déploiement

```bash
cd tp1

# Définir le mot de passe RDS
# Windows PowerShell :
$env:TF_VAR_db_password = "VotreMotDePasseSecurise123!"
# Linux/Mac :
export TF_VAR_db_password="VotreMotDePasseSecurise123!"

terraform init
terraform plan
terraform apply -auto-approve
# Durée : environ 15-20 minutes
```

### Configuration initiale de Pritunl

#### 1. Récupérer la clé de setup
```bash
# Lister les instances de l'ASG
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names keyce-tp2-asg \
    --query "AutoScalingGroups[0].Instances[*].InstanceId" \
    --output text

# Se connecter via SSM (sans clé SSH)
aws ssm start-session --target <INSTANCE_ID>

# Dans la session SSM :
cat /root/pritunl-setup-key.txt
```

#### 2. Accéder à Pritunl
Ouvrir : `https://<IP_PUBLIQUE_INSTANCE>`

#### 3. Configurer le serveur VPN
1. Entrer la **setup-key**
2. MongoDB URI : `mongodb://localhost:27017/pritunl`
3. Changer le mot de passe admin
4. **Users** → Add Organization → Add User
5. **Servers** → Add Server : Port `1194`, Protocol `udp`
6. Attach Organization → Start Server
7. Télécharger le fichier `.ovpn`

---

## TP2 — Déploiement Applicatif Odoo en HA

### Objectif
Utiliser l'infrastructure VPN du TP1 pour créer un environnement **hybride** et déployer Odoo 17 en haute disponibilité.

### Étape 1 — Connexion VPN (Hybridation)

```bash
# Linux/Debian :
sudo openvpn --config votre-profil.ovpn --daemon

# Vérifier la connexion VPN
ip addr show tun0
```

Une fois connecté, vous pouvez accéder aux instances EC2 via leurs **IPs privées** (`10.0.1.11`, `10.0.2.40`) comme si elles étaient sur votre réseau local. C'est l'aspect **hybride** de l'architecture.

### Étape 2 — Déploiement Odoo avec EFS partagé

#### Créer l'EFS
```powershell
# Créer le système de fichiers EFS
$efsId = (aws efs create-file-system `
  --performance-mode generalPurpose `
  --throughput-mode bursting `
  --tags Key=Name,Value=efs-odoo-filestore `
  --query 'FileSystemId' --output text)

# Créer les mount targets dans les deux subnets
aws efs create-mount-target `
  --file-system-id $efsId `
  --subnet-id subnet-0e1c3f358f8870021 `
  --security-groups <SG_EFS_ID>

aws efs create-mount-target `
  --file-system-id $efsId `
  --subnet-id subnet-0362366b537ec91bd `
  --security-groups <SG_EFS_ID>
```

#### Monter l'EFS sur les deux instances
```bash
# Sur chaque instance EC2
yum install -y amazon-efs-utils
mkdir -p /mnt/efs
mount -t efs <EFS_ID>:/ /mnt/efs
mkdir -p /mnt/efs/odoo-filestore
```

#### Lancer Odoo avec le volume EFS
```bash
# Sur les deux instances
docker run -d \
  --name odoo-app \
  --restart always \
  -p 8069:8069 \
  -e HOST=10.0.2.40 \
  -e USER=odoo \
  -e PASSWORD=odoo_password \
  -e DATABASE=keyce_odoo \
  -v /mnt/efs/odoo-filestore:/var/lib/odoo \
  odoo:17
```

---

## Haute Disponibilité Base de Données — Patroni

### Pourquoi Patroni ?
Patroni est une solution open-source de HA PostgreSQL utilisée en production dans de grandes entreprises. Il maintient une réplication **synchrone** entre un nœud Primary et un nœud Standby avec **basculement automatique** via etcd — l'équivalent self-managed de RDS Multi-AZ.

```
[Odoo 1] ──┐
           ├──► [PostgreSQL PRIMARY 10.0.2.40] 
[Odoo 2] ──┘         │ Réplication Synchrone (Lag=0)
                [PostgreSQL STANDBY 10.0.1.11]
                      │
                   [etcd — Arbitre]
                   Élit le Leader auto
```

### Installation (sur les deux instances)

```bash
# Dépendances
yum install -y python3-pip python3-devel gcc gcc-c++ postgresql15-server postgresql15

# etcd (sur instance 1 uniquement — arbitre)
curl -L https://github.com/etcd-io/etcd/releases/download/v3.5.9/etcd-v3.5.9-linux-amd64.tar.gz -o /tmp/etcd.tar.gz
tar -xzf /tmp/etcd.tar.gz -C /tmp
mv /tmp/etcd-v3.5.9-linux-amd64/etcd /usr/local/bin/
mv /tmp/etcd-v3.5.9-linux-amd64/etcdctl /usr/local/bin/

# Patroni
pip3 install patroni[etcd3] psycopg2-binary
```

### Configuration Patroni — node1 (PRIMARY, 10.0.2.40)

```yaml
# /etc/patroni/patroni.yml
scope: odoo-cluster
namespace: /db/
name: node1

restapi:
  listen: 10.0.2.40:8008
  connect_address: 10.0.2.40:8008

etcd3:
  host: 10.0.2.40:2379

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    synchronous_mode: true
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - host replication replicator 10.0.0.0/16 md5
    - host all all 0.0.0.0/0 md5
  users:
    odoo:
      password: odoo_password
      options:
        - createdb
        - createrole

postgresql:
  listen: 10.0.2.40:5432
  connect_address: 10.0.2.40:5432
  data_dir: /var/lib/pgsql/15/patroni
  bin_dir: /usr/bin
  pgpass: /tmp/pgpass
  authentication:
    replication:
      username: replicator
      password: replicator_password
    superuser:
      username: postgres
      password: postgres_password
```

> Pour node2 (STANDBY, 10.0.1.11) : remplacer `name: node1` par `name: node2` et toutes les occurrences de `10.0.2.40` par `10.0.1.11` sauf pour `etcd3.host`.

### Démarrage

```bash
# Sur instance 1 — démarrer etcd
systemctl enable etcd && systemctl start etcd

# Sur les deux instances — démarrer Patroni
systemctl enable patroni && systemctl start patroni

# Vérifier le cluster
patronictl -c /etc/patroni/patroni.yml list
```

Résultat attendu :
```
+ Cluster: odoo-cluster ----+----+-------------+-----+
| Member | Host      | Role         | State     | TL |
+--------+-----------+--------------+-----------+----+
| node1  | 10.0.2.40 | Leader       | running   |  1 |
| node2  | 10.0.1.11 | Sync Standby | streaming |  1 |
+--------+-----------+--------------+-----------+----+
```

### Import de la base de données

```bash
# Export depuis l'ancien PostgreSQL Docker
docker exec odoo-db pg_dump -U odoo keyce-odoo > /tmp/keyce-odoo-backup.sql

# Import dans Patroni
sudo -u postgres psql -c "CREATE DATABASE keyce_odoo;"
sudo -u postgres psql -c "CREATE USER odoo WITH PASSWORD 'odoo_password' CREATEDB CREATEROLE;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE keyce_odoo TO odoo;"
sudo -u postgres psql -d keyce_odoo -f /tmp/keyce-odoo-backup.sql
```

---

## Haute Disponibilité Filestore — lsyncd

### Pourquoi lsyncd ?
lsyncd synchronise le filestore Odoo en temps réel entre les deux instances via rsync+SSH. La synchronisation est **bidirectionnelle** — un fichier uploadé sur n'importe quelle instance est copié sur l'autre en moins de 5 secondes.

```
[/mnt/efs/odoo-filestore — Instance 1]
        │                    ▲
        │ lsyncd (5s)        │ lsyncd (5s)
        ▼                    │
[/mnt/efs-backup/odoo-filestore — Instance 2]
```

### Installation (sur les deux instances)

```bash
yum install -y gcc gcc-c++ cmake lua lua-devel rsync
curl -L https://github.com/lsyncd/lsyncd/archive/refs/tags/release-2.3.1.tar.gz -o /tmp/lsyncd.tar.gz
tar -xzf /tmp/lsyncd.tar.gz -C /tmp
cd /tmp/lsyncd-release-2.3.1
cmake . && make && make install
lsyncd --version
```

### Configuration SSH sans mot de passe

```bash
# Sur chaque instance — générer une clé SSH
ssh-keygen -t rsa -b 2048 -f ~/.ssh/lsyncd_key -N ""

# Copier la clé publique vers l'autre instance
# (ajouter dans ~/.ssh/authorized_keys de l'instance cible)

# Tester la connexion
ssh -i ~/.ssh/lsyncd_key root@<IP_AUTRE_INSTANCE> "echo SSH OK"
```

### Configuration lsyncd — Instance 1 (vers Instance 2)

```lua
-- /etc/lsyncd/lsyncd.conf.lua
settings {
    logfile    = "/var/log/lsyncd.log",
    statusFile = "/var/log/lsyncd.status",
    statusInterval = 10,
}

sync {
    default.rsyncssh,
    source    = "/mnt/efs/odoo-filestore/",
    host      = "10.0.1.11",
    targetdir = "/mnt/efs-backup/odoo-filestore/",
    rsync = {
        archive  = true,
        compress = true,
        verbose  = true,
    },
    ssh = {
        identityFile = "/root/.ssh/lsyncd_key",
    },
    delay = 5,
}
```

> Pour Instance 2 : remplacer `host = "10.0.1.11"` par `host = "10.0.2.40"`.

### Démarrage

```bash
# Service systemd
cat > /etc/systemd/system/lsyncd.service << 'EOF'
[Unit]
Description=lsyncd - Live Syncing Daemon
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/bin/lsyncd /etc/lsyncd/lsyncd.conf.lua
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable lsyncd
systemctl start lsyncd
```

### Test de la réplication

```bash
# Créer un fichier test sur instance 1
touch /mnt/efs/odoo-filestore/TEST-LSYNCD-$(date +%s)

# Vérifier après 10 secondes sur instance 2
sleep 10
ssh -i ~/.ssh/lsyncd_key root@10.0.1.11 "ls /mnt/efs-backup/odoo-filestore/TEST*"
# Résultat attendu : le fichier apparaît ✅
```

---

## Load Balancer Odoo HA

### Création de l'ALB Odoo

```powershell
# Target Group
$tgArn = (aws elbv2 create-target-group `
  --name "tg-odoo-ha" `
  --protocol HTTP `
  --port 8069 `
  --vpc-id vpc-0e3bcbe70f17cd100 `
  --health-check-path "/web/health" `
  --health-check-interval-seconds 30 `
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Enregistrer les deux instances
aws elbv2 register-targets `
  --target-group-arn $tgArn `
  --targets Id=<INSTANCE_1_ID>,Port=8069 Id=<INSTANCE_2_ID>,Port=8069

# Créer l'ALB
$albArn = (aws elbv2 create-load-balancer `
  --name "alb-odoo-ha" `
  --subnets subnet-0e1c3f358f8870021 subnet-0362366b537ec91bd `
  --security-groups <SG_ALB_ID> `
  --scheme internet-facing `
  --type application `
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Créer le Listener
aws elbv2 create-listener `
  --load-balancer-arn $albArn `
  --protocol HTTP `
  --port 80 `
  --default-actions Type=forward,TargetGroupArn=$tgArn
```

### Accès à Odoo via le ALB

```
http://alb-odoo-ha-XXXXXXX.us-east-1.elb.amazonaws.com
```

---

## Test de résilience

### Test 1 — Résilience applicative (Odoo)

```bash
# 1. Créer un enregistrement TEST-RESILIENCE-001 dans Odoo via l'instance 1
# 2. Arrêter Odoo sur l'instance 1
aws ssm start-session --target <INSTANCE_1_ID>
docker stop odoo-app

# 3. Vérifier que l'instance 2 répond toujours
# Ouvrir : http://<IP_INSTANCE_2>:8069
# Les données doivent être présentes ✅

# 4. Redémarrer (--restart always le fait automatiquement)
docker start odoo-app
```

### Test 2 — Résilience base de données (Patroni)

```bash
# 1. Vérifier l'état initial du cluster
patronictl -c /etc/patroni/patroni.yml list

# 2. Arrêter Patroni sur le PRIMARY (node1)
systemctl stop patroni  # sur instance 1

# 3. Vérifier le failover automatique (attendre ~30 secondes)
patronictl -c /etc/patroni/patroni.yml list
# node2 doit être promu Leader automatiquement ✅

# 4. Redémarrer node1 (devient automatiquement Standby)
systemctl start patroni
```

### Test 3 — Résilience filestore (lsyncd)

```bash
# 1. Uploader une image dans Odoo sur instance 1
# 2. Vérifier après 10 secondes sur instance 2
ssh -i ~/.ssh/lsyncd_key root@10.0.1.11 \
  "ls -la /mnt/efs-backup/odoo-filestore/filestore/keyce_odoo/"
# Le fichier doit apparaître ✅
```

---

## Nettoyage des ressources

> ⚠️ Les NAT Gateways et EFS coûtent. Détruire après la démo !

```bash
# Supprimer l'ALB Odoo
aws elbv2 delete-load-balancer --load-balancer-arn <ALB_ARN>
aws elbv2 delete-target-group --target-group-arn <TG_ARN>

# Supprimer l'EFS
aws efs delete-mount-target --mount-target-id <MT_ID>
aws efs delete-file-system --file-system-id <EFS_ID>

# Vider le bucket S3
aws s3 rm s3://<NOM_BUCKET> --recursive

# Détruire l'infrastructure TP1
cd tp1
export TF_VAR_db_password="VotreMotDePasse"
terraform destroy -auto-approve
```

---

## Dépannage

### Terraform init échoue
```bash
rm -rf .terraform && terraform init
```

### VPN connecté mais pas d'accès aux instances
```bash
ip addr show tun0
ping <IP_PRIVEE_INSTANCE>
```

### Pritunl ne démarre pas
```bash
sudo systemctl status pritunl mongod
sudo tail -50 /var/log/pritunl-install.log
```

### Odoo page blanche après connexion
```bash
# Vider le cache des assets
sudo -u postgres psql -d keyce_odoo \
  -c "DELETE FROM ir_attachment WHERE url LIKE '/web/assets/%';"
docker restart odoo-app
```

### Patroni — node en échec
```bash
# Vérifier les logs
journalctl -u patroni -n 50 --no-pager

# Vérifier etcd
etcdctl --endpoints=http://10.0.2.40:2379 endpoint health

# Réinitialiser un node
patronictl -c /etc/patroni/patroni.yml reinit odoo-cluster <NODE_NAME>
```

### lsyncd ne synchronise pas
```bash
# Vérifier les logs
cat /var/log/lsyncd.log | tail -30

# Tester rsync manuellement
rsync -avz -e "ssh -i ~/.ssh/lsyncd_key" \
  /mnt/efs/odoo-filestore/ root@10.0.1.11:/mnt/efs-backup/odoo-filestore/

# Vérifier que rsync est installé sur l'instance cible
ssh -i ~/.ssh/lsyncd_key root@10.0.1.11 "rsync --version"
```

### EFS non monté après reboot
```bash
# Ajouter au /etc/fstab pour montage automatique
echo "<EFS_ID>:/ /mnt/efs efs defaults,_netdev 0 0" >> /etc/fstab
mount -a
```

---

## Auteur

**Nell Mvele** — B3 Réseaux & Sécurité Informatique
Keyce Informatique et Intelligence Artificielle — 2025-2026
