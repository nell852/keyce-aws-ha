# TP AWS — Infrastructure Cloud Haute Disponibilité avec VPN Pritunl et Odoo
## Keyce Informatique — B3 Réseaux & Sécurité Informatique
## Auteur : Nell Mvele

---

## 📋 Table des matières

1. [Présentation](#présentation)
2. [Architecture globale](#architecture-globale)
3. [Prérequis](#prérequis)
4. [TP1 — Infrastructure HA avec VPN Pritunl](#tp1--infrastructure-ha-avec-vpn-pritunl)
5. [TP2 — Déploiement Applicatif Odoo en HA](#tp2--déploiement-applicatif-odoo-en-ha)
6. [Test de résilience](#test-de-résilience)
7. [Nettoyage des ressources](#nettoyage-des-ressources)
8. [Dépannage](#dépannage)

---

## Présentation

Ce projet déploie une infrastructure cloud AWS complète en deux étapes :

- **TP1** : Architecture Haute Disponibilité avec VPN Pritunl sur AWS.
  - VPC multi-AZ, Auto Scaling Group, Application Load Balancer, RDS MySQL Multi-AZ, S3 + Lambda.
  - Déployé via **Terraform** (Infrastructure as Code).

- **TP2** : Déploiement applicatif automatisé d'Odoo 17 en mode HA.
  - Hybridation réseau local ↔ AWS via VPN Pritunl.
  - Application Odoo 17 conteneurisée avec Docker en Master-Master.
  - Test de résilience : vérification du basculement automatique.

---

## Architecture globale

\`\`\`
Réseau Local (Debian)
    │
    │ VPN OpenVPN (Pritunl)
    │
Internet
    │
    ├── HTTPS :443 ──► Application Load Balancer (ALB)
    │                        │
    │              ┌─────────┴─────────┐
    │         AZ us-east-1a      AZ us-east-1b
    │         EC2 t3.small       EC2 t3.small
    │         Pritunl VPN        Pritunl VPN
    │         Odoo 17 Docker     Odoo 17 Docker
    │              │                   │
    │              └────────┬──────────┘
    │                  PostgreSQL partagé
    │
    ├── RDS MySQL 8.0 Multi-AZ
    ├── S3 Bucket + Lambda Python
    └── CloudWatch (monitoring CPU)
\`\`\`

---

## Prérequis

### Outils à installer

#### 1. AWS CLI
Télécharger : https://aws.amazon.com/fr/cli/
\`\`\`bash
aws --version
\`\`\`

#### 2. Terraform (>= 1.5)
Télécharger : https://developer.hashicorp.com/terraform/downloads
\`\`\`bash
terraform version
\`\`\`

#### 3. Configurer AWS CLI
\`\`\`bash
aws configure
# AWS Access Key ID     : votre_access_key
# AWS Secret Access Key : votre_secret_key
# Default region name   : us-east-1
# Default output format : json

# Vérifier :
aws sts get-caller-identity
\`\`\`

#### 4. Docker et Docker Compose (pour TP2)
Télécharger : https://www.docker.com/products/docker-desktop/
\`\`\`bash
docker --version
docker compose version
\`\`\`

#### 5. Client OpenVPN (pour TP2)
- **Windows/Mac** : https://openvpn.net/client/
- **Linux/Debian** :
\`\`\`bash
sudo apt install openvpn -y
\`\`\`

---

## TP1 — Infrastructure HA avec VPN Pritunl

### Ce qui est déployé
- **VPC** 10.0.0.0/16 multi-AZ (2 subnets publics + 2 privés)
- **2 NAT Gateways** (un par AZ)
- **Application Load Balancer** avec SSL
- **Auto Scaling Group** : min 2, max 4 instances EC2 t3.small
- **Pritunl VPN** sur chaque instance (OpenVPN/WireGuard)
- **RDS MySQL 8.0** Multi-AZ
- **S3 Bucket** (versionné, chiffré AES256)
- **Lambda Python 3.12** (traitement automatique des logs)
- **CloudWatch** (alertes CPU scale-up/down)

### Structure des fichiers Terraform

\`\`\`
tp1/
├── main.tf           # VPC, subnets, NAT Gateways, routes
├── ec2_asg.tf        # Launch Template, ALB, ASG, CloudWatch
├── rds.tf            # Base de données MySQL Multi-AZ
├── s3_lambda.tf      # Bucket S3 + fonction Lambda
├── security_groups.tf # Règles de sécurité réseau
├── variables.tf      # Variables configurables
├── versions.tf       # Providers Terraform
└── outputs.tf        # Valeurs exportées après déploiement
\`\`\`

### Déploiement

\`\`\`bash
cd tp1

# Définir le mot de passe RDS
# Windows PowerShell :
\$env:TF_VAR_db_password = "VotreMotDePasseSecurise123!"
# Linux/Mac :
export TF_VAR_db_password="VotreMotDePasseSecurise123!"

terraform init
terraform plan
terraform apply -auto-approve
# Durée : environ 15-20 minutes (RDS Multi-AZ)
\`\`\`

### Résultats attendus

\`\`\`
alb_dns_name         = "keyce-tp2-alb-XXXXXXX.us-east-1.elb.amazonaws.com"
pritunl_ui_url       = "https://keyce-tp2-alb-XXXXXXX.us-east-1.elb.amazonaws.com"
s3_bucket_name       = "keyce-tp2-storage-XXXXXXXXXXXX"
lambda_function_name = "keyce-tp2-log-processor"
asg_name             = "keyce-tp2-asg"
\`\`\`

### Configuration initiale de Pritunl

#### 1. Récupérer la clé de setup
\`\`\`bash
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names keyce-tp2-asg \
    --query "AutoScalingGroups[0].Instances[*].InstanceId" \
    --output text

aws ssm start-session --target <INSTANCE_ID>

cat /root/pritunl-setup-key.txt
\`\`\`

#### 2. Accéder à Pritunl
Ouvrir : \`https://<IP_PUBLIQUE_INSTANCE>\`
(Accepter l'avertissement SSL — certificat auto-signé)

#### 3. Configurer le serveur VPN
1. Entrer la **setup-key**
2. MongoDB URI par défaut : \`mongodb://localhost:27017/pritunl\`
3. Changer le mot de passe admin
4. **Users** → Add Organization → Add User
5. **Servers** → Add Server :
   - Port : \`1194\`, Protocol : \`udp\`, WireGuard : **décoché**
6. Attach Organization → Start Server
7. Télécharger le fichier \`.ovpn\`

---

## TP2 — Déploiement Applicatif Odoo en HA

### Objectif
Utiliser l'infrastructure VPN du TP1 pour créer un environnement hybride et déployer Odoo 17 en haute disponibilité via Docker.

### Architecture technique
- **Hybridation** : Réseau local connecté à AWS via VPN Pritunl
- **Conteneurisation** : Docker + Docker Compose
- **Application** : Odoo 17
- **HA** : 2 instances Odoo partageant le même PostgreSQL (Master-Master)

### Structure des fichiers

\`\`\`
odoo-ha/
└── docker-compose.yml    # Définition des conteneurs Odoo + PostgreSQL
\`\`\`

### Étape 1 — Connexion VPN (Hybridation)

\`\`\`bash
sudo openvpn --config votre-profil.ovpn --daemon
ip addr show tun0
curl ifconfig.me
\`\`\`

### Étape 2 — Déploiement Odoo sur Instance 1 (Nœud Maître)

\`\`\`bash
ssh -i keyce-tp2-key.pem ec2-user@<IP_PRIVEE_INSTANCE_1>
mkdir -p ~/odoo-ha && cd ~/odoo-ha
docker-compose up -d
docker-compose ps
\`\`\`

Accéder à Odoo : \`http://<IP_PUBLIQUE_1>:8069\`

### Étape 3 — Déploiement Odoo sur Instance 2 (Nœud Esclave)

\`\`\`bash
cat > ~/odoo-ha/docker-compose.yml <<'DOCKEREOF'
services:
  odoo:
    image: odoo:17
    container_name: odoo-app
    ports:
      - "8069:8069"
    environment:
      HOST: <IP_PRIVEE_INSTANCE_1>
      USER: odoo
      PASSWORD: odoo_password
    volumes:
      - odoo-web-data:/var/lib/odoo
    restart: always

volumes:
  odoo-web-data:
DOCKEREOF

docker-compose up -d
\`\`\`

### Étape 4 — Synchronisation du Filestore

\`\`\`bash
docker cp odoo-app:/var/lib/odoo/filestore /tmp/odoo-filestore
aws s3 cp /tmp/odoo-filestore s3://<BUCKET_NAME>/odoo-filestore/ --recursive
aws s3 cp s3://<BUCKET_NAME>/odoo-filestore/ /tmp/odoo-filestore/ --recursive
docker cp /tmp/odoo-filestore odoo-app:/var/lib/odoo/filestore/keyce-odoo
docker restart odoo-app
\`\`\`

---

## Test de résilience

### Procédure

\`\`\`bash
ssh -i keyce-tp2-key.pem ec2-user@<IP_INSTANCE_1> "docker stop odoo-app"
curl http://<IP_INSTANCE_2>:8069
ssh -i keyce-tp2-key.pem ec2-user@<IP_INSTANCE_1> "docker start odoo-app"
\`\`\`

### Résultat attendu
✅ Les données sont accessibles sur l'instance 2 même quand l'instance 1 est arrêtée.

---

## Nettoyage des ressources

> ⚠️ Les NAT Gateways coûtent ~\$3/jour. Détruire après la démo !

\`\`\`bash
aws s3 rm s3://<NOM_BUCKET> --recursive
cd tp1
export TF_VAR_db_password="VotreMotDePasse"
terraform destroy -auto-approve
\`\`\`

---

## Dépannage

### Terraform init échoue
\`\`\`bash
rm -rf .terraform && terraform init
\`\`\`

### Erreur AccessDenied AWS
\`\`\`bash
aws iam list-attached-user-policies --user-name <USER>
\`\`\`

### VPN connecté mais pas d'accès aux instances
\`\`\`bash
ip addr show tun0
ping <IP_PRIVEE_INSTANCE>
\`\`\`

### Pritunl ne démarre pas
\`\`\`bash
sudo tail -50 /var/log/pritunl-install.log
sudo systemctl status pritunl mongod
\`\`\`

### Odoo page blanche après connexion
\`\`\`bash
docker exec odoo-app odoo -d keyce-odoo \
    --db_host=<IP_POSTGRES> \
    --db_user=odoo \
    --db_password=odoo_password \
    --update=web --stop-after-init
docker restart odoo-app
\`\`\`

---

## Auteur

**Nell Mvele** — B3 Réseaux & Sécurité Informatique
Keyce Informatique et Intelligence Artificielle — 2025-2026
