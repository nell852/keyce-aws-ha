# AWS TPs – Keyce Informatique B3 – Réseaux & Sécurité
## Terraform sur AWS CLI

---

## PRÉ-REQUIS

```powershell
# Vérifier que vous êtes connecté
aws sts get-caller-identity

# Installer Terraform (si pas encore fait)
# Télécharger depuis https://developer.hashicorp.com/terraform/downloads
# Ou via chocolatey :
choco install terraform

# Vérifier la version
terraform version   # >= 1.5 requis
```

---

## TP1 – EC2 + EBS + Snapshot + AMI personnalisée

### Architecture déployée
```
Internet
   │
   ├── Port 80  (HTTP)  → EC2 t3.micro (Apache)
   └── Port 22  (SSH)   → EC2 (votre IP uniquement)
                              │
                         Volume EBS gp3 10Go (/dev/xvdf → /data)
                              │
                         Snapshot → AMI personnalisée
```

### Déploiement

```powershell
cd tp1

# Initialisation des providers
terraform init

# Aperçu des ressources à créer
terraform plan

# Déploiement (confirmation requise)
terraform apply

# OU sans confirmation interactive :
terraform apply -auto-approve
```

### Outputs attendus après apply

```
instance_id         = "i-0abc123..."
instance_public_ip  = "54.X.X.X"
web_url             = "http://54.X.X.X"
ssh_command         = "ssh -i keyce-tp1-key.pem ec2-user@54.X.X.X"
ebs_volume_id       = "vol-0abc123..."
snapshot_id         = "snap-0abc123..."
custom_ami_id       = "ami-0abc123..."
```

### Monter le volume EBS /data (après SSH)

```bash
# Se connecter à l'instance
ssh -i keyce-tp1-key.pem ec2-user@<IP_PUBLIQUE>

# Formater le volume (EXT4)
sudo mkfs.ext4 /dev/xvdf

# Créer le point de montage
sudo mkdir -p /data

# Monter le volume
sudo mount /dev/xvdf /data

# Montage permanent (survit aux reboots)
echo '/dev/xvdf /data ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab

# Vérifier
df -h /data
lsblk
```

### Vérification Apache

```bash
# Depuis l'instance :
systemctl status httpd
curl http://localhost

# Depuis votre machine :
curl http://<IP_PUBLIQUE>
```

### Nettoyage TP1

```powershell
terraform destroy -auto-approve
```

> ⚠️ L'AMI et le snapshot ne sont PAS supprimés automatiquement par Terraform.
> Supprimer manuellement depuis la console AWS EC2 > AMIs et EC2 > Snapshots.

---

## TP2 – Architecture HA avec Auto Scaling + Pritunl VPN

### Architecture déployée

```
Internet
    │
    ├── HTTP :80  → ALB (redirige vers HTTPS)
    └── HTTPS :443 → ALB
                      │
              ┌───────┴───────┐
              │  Target Group │
              └───────┬───────┘
                      │
         ┌────────────┴────────────┐
         │    Auto Scaling Group   │
         │  min=2, max=4, desired=2│
         ├─────────────────────────┤
         │ AZ us-east-1a           │  AZ us-east-1b
         │ EC2 t3.small (Pritunl)  │  EC2 t3.small (Pritunl)
         │ Subnet Privé 10.0.11.0  │  Subnet Privé 10.0.12.0
         └────────────────────────┘
                      │
              ┌───────┴───────┐
              │  RDS MySQL    │  Multi-AZ (db.t3.micro)
              │  10.0.11/12   │
              └───────────────┘

S3 Bucket ──→ Trigger ──→ Lambda Python (analyse logs Pritunl)

Subnets Publics (NAT Gateway × 2) pour sortie internet des privés
```

### Déploiement

```powershell
cd tp2

# Le mot de passe RDS est requis – définir via variable d'environnement :
$env:TF_VAR_db_password = "MotDePasseSecurise123!"

# Initialisation
terraform init

# Plan
terraform plan

# Déploiement (prend ~15-20 minutes pour RDS Multi-AZ)
terraform apply -auto-approve
```

### Outputs attendus

```
alb_dns_name        = "keyce-tp2-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com"
pritunl_ui_url      = "https://keyce-tp2-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com"
rds_endpoint        = "keyce-tp2-mysql.xxxx.us-east-1.rds.amazonaws.com:3306"
s3_bucket_name      = "keyce-tp2-storage-679409142918"
lambda_function_name = "keyce-tp2-log-processor"
asg_name            = "keyce-tp2-asg"
```

### Configuration initiale Pritunl

```powershell
# 1. Lister les instances de l'ASG
aws autoscaling describe-auto-scaling-groups `
    --auto-scaling-group-names keyce-tp2-asg `
    --query "AutoScalingGroups[0].Instances[*].InstanceId" `
    --output text

# 2. Récupérer la setup-key via SSM (pas besoin de SSH !)
aws ssm start-session --target <INSTANCE_ID>
# Puis dans la session :
cat /root/pritunl-setup-key.txt

# 3. Ouvrir https://<ALB_DNS> dans le navigateur
# 4. Entrer la setup-key affichée
# 5. Login : pritunl / pritunl (changer immédiatement)
# 6. Créer Organization > User > Server VPN
# 7. Télécharger le profil .ovpn
```

### Tester Lambda (traitement des logs)

```powershell
# Uploader un log de test
echo "2024-01-01 12:00:00 Connected user1 from 192.168.1.1" | `
    aws s3 cp - s3://keyce-tp2-storage-679409142918/logs/test.log

# Voir les logs Lambda
aws logs tail /aws/lambda/keyce-tp2-log-processor --follow

# Vérifier le résumé généré
aws s3 ls s3://keyce-tp2-storage-679409142918/summaries/
```

### Tester l'Auto Scaling

```powershell
# Voir l'état de l'ASG
aws autoscaling describe-auto-scaling-groups `
    --auto-scaling-group-names keyce-tp2-asg

# Forcer un scale-out manuel (pour le TP)
aws autoscaling set-desired-capacity `
    --auto-scaling-group-name keyce-tp2-asg `
    --desired-capacity 3

# Revenir à 2
aws autoscaling set-desired-capacity `
    --auto-scaling-group-name keyce-tp2-asg `
    --desired-capacity 2
```

### Nettoyage TP2

```powershell
# Vider le bucket S3 d'abord (obligatoire avant destruction)
aws s3 rm s3://keyce-tp2-storage-679409142918 --recursive

# Détruire toute l'infrastructure
terraform destroy -auto-approve
```

---

## COÛTS ESTIMÉS (Free Tier)

| Ressource       | TP1        | TP2           | Notes                    |
|-----------------|-----------|---------------|--------------------------|
| EC2 t3.micro    | ~0$       | ~0$ (×2)      | Free tier 750h/mois      |
| EC2 t3.small    | N/A       | ~$0.023/h ×2  | Hors free tier           |
| EBS 20Go gp3    | ~0$       | incl. EC2     | 30Go gratuits/mois       |
| RDS db.t3.micro | N/A       | ~$0.017/h     | 750h/mois free tier      |
| ALB             | N/A       | ~$0.008/h     | Hors free tier           |
| NAT Gateway ×2  | N/A       | ~$0.045/h ×2  | ⚠️ Plus coûteux          |
| S3              | N/A       | ~0$           | 5Go gratuits             |
| Lambda          | N/A       | ~0$           | 1M invocations gratuites |

> ⚠️ **Détruire les ressources après le TP** pour éviter des frais, surtout les NAT Gateways.
> Les NAT Gateways coûtent ~$32/mois chacune si laissées actives.

---

## DÉPANNAGE

### Terraform init échoue
```powershell
# Supprimer le cache et réessayer
Remove-Item -Recurse -Force .terraform
terraform init
```

### Erreur "AccessDenied"
```powershell
# Vérifier les permissions IAM
aws iam get-user
aws iam list-attached-user-policies --user-name aws-cli-user
```

### Instance ne démarre pas
```powershell
# Vérifier les logs user-data
aws ec2 get-console-output --instance-id <ID> --latest
```

### Pritunl n'est pas accessible
```powershell
# Vérifier les health checks ALB
aws elbv2 describe-target-health `
    --target-group-arn <TG_ARN>

# L'installation de Pritunl prend ~5 min après démarrage
# Attendre que le health check passe en "healthy"
```
