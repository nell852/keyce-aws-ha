###############################################################
# TP1 – EC2 + EBS + Snapshot + AMI personnalisée
# Keyce Informatique – Réseaux & Sécurité – B3
###############################################################

provider "aws" {
  region = var.aws_region
}

###############################################################
# 1. DATA – Récupération de l'AMI Amazon Linux 2023
###############################################################
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Récupération de l'IP publique de la machine qui lance Terraform
data "http" "my_public_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip = "${chomp(data.http.my_public_ip.response_body)}/32"
}

###############################################################
# 2. KEY PAIR SSH
###############################################################
resource "tls_private_key" "keyce_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "keyce_keypair" {
  key_name   = "${var.project_name}-keypair"
  public_key = tls_private_key.keyce_key.public_key_openssh
}

# Sauvegarde locale de la clé privée
resource "local_file" "private_key" {
  content         = tls_private_key.keyce_key.private_key_pem
  filename        = "${path.module}/${var.project_name}-key.pem"
  file_permission = "0400"
}

###############################################################
# 3. SECURITY GROUP
###############################################################
resource "aws_security_group" "tp1_sg" {
  name        = "${var.project_name}-sg"
  description = "SG TP1 - SSH restreint + HTTP public"

  # SSH uniquement depuis votre IP
  ingress {
    description = "SSH depuis mon IP uniquement"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  # HTTP depuis internet
  ingress {
    description = "HTTP depuis internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Tout le trafic sortant autorisé
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
    TP      = "TP1"
  }
}

###############################################################
# 4. USER DATA – Installation Apache + page d'accueil
###############################################################
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e
    # Mise à jour du système
    dnf update -y

    # Installation d'Apache
    dnf install -y httpd

    # Activation et démarrage du service
    systemctl enable httpd
    systemctl start httpd

    # Page d'accueil personnalisée
    cat > /var/www/html/index.html <<'HTML'
    <!DOCTYPE html>
    <html lang="fr">
    <head>
      <meta charset="UTF-8">
      <title>Keyce – TP1 AWS</title>
      <style>
        body { font-family: Arial, sans-serif; background: #0d1117; color: #58a6ff; 
               display: flex; align-items: center; justify-content: center; 
               min-height: 100vh; margin: 0; }
        .card { background: #161b22; border: 1px solid #30363d; border-radius: 12px;
                padding: 40px; text-align: center; max-width: 500px; }
        h1 { color: #f0f6fc; margin-bottom: 10px; }
        .badge { background: #238636; color: white; padding: 4px 12px; 
                 border-radius: 20px; font-size: 12px; }
        p { color: #8b949e; }
      </style>
    </head>
    <body>
      <div class="card">
        <span class="badge">✓ Apache opérationnel</span>
        <h1>🎓 Keyce Informatique</h1>
        <h2>TP1 – EC2 Amazon Linux 2023</h2>
        <p>Instance EC2 déployée avec Terraform</p>
        <p>Type : <strong>t3.micro</strong> | AMI : <strong>Amazon Linux 2023</strong></p>
        <p>Volume EBS additionnel monté sur <code>/data</code></p>
        <hr style="border-color:#30363d">
        <p style="font-size:12px;">Réseaux & Sécurité Informatique – B3</p>
      </div>
    </body>
    </html>
    HTML

    echo "User data script terminé avec succès" >> /var/log/tp1-setup.log
  EOF
}

###############################################################
# 5. INSTANCE EC2
###############################################################
resource "aws_instance" "tp1_instance" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  key_name               = aws_key_pair.keyce_keypair.key_name
  vpc_security_group_ids = [aws_security_group.tp1_sg.id]

  # Volume racine – gp3, 20 Go
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true

    tags = {
      Name = "${var.project_name}-root-volume"
    }
  }

  user_data = local.user_data

  # Désactive l'arrêt accidentel depuis la console
  disable_api_termination = false

  tags = {
    Name    = "${var.project_name}-instance"
    Project = var.project_name
    TP      = "TP1"
  }
}

###############################################################
# 6. VOLUME EBS SUPPLÉMENTAIRE – gp3 10 Go
###############################################################
resource "aws_ebs_volume" "data_volume" {
  availability_zone = aws_instance.tp1_instance.availability_zone
  size              = 10
  type              = "gp3"
  encrypted         = true

  tags = {
    Name    = "${var.project_name}-data-volume"
    Project = var.project_name
    TP      = "TP1"
  }
}

# Attachement du volume à l'instance
resource "aws_volume_attachment" "data_attachment" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data_volume.id
  instance_id = aws_instance.tp1_instance.id

  # Force le détachement à la destruction
  force_detach = true
}

###############################################################
# 7. ELASTIC IP (optionnel mais pratique)
###############################################################
resource "aws_eip" "tp1_eip" {
  instance = aws_instance.tp1_instance.id
  domain   = "vpc"

  tags = {
    Name    = "${var.project_name}-eip"
    Project = var.project_name
  }
}

###############################################################
# 8. SNAPSHOT DU VOLUME RACINE
###############################################################
resource "aws_ebs_snapshot" "root_snapshot" {
  # On récupère l'ID du volume racine depuis l'instance
  volume_id   = aws_instance.tp1_instance.root_block_device[0].volume_id
  description = "Snapshot volume racine - ${var.project_name} TP1"

  tags = {
    Name    = "${var.project_name}-root-snapshot"
    Project = var.project_name
    TP      = "TP1"
  }

  depends_on = [aws_instance.tp1_instance]
}

###############################################################
# 9. AMI PERSONNALISÉE à partir de l'instance
###############################################################
resource "aws_ami_from_instance" "keyce_ami" {
  name               = "${var.project_name}-custom-ami"
  source_instance_id = aws_instance.tp1_instance.id
  description        = "AMI Keyce TP1 - Apache preinstalle"

  # L'AMI ne sera pas supprimée automatiquement (à gérer manuellement)
  snapshot_without_reboot = true

  tags = {
    Name    = "${var.project_name}-ami"
    Project = var.project_name
    TP      = "TP1"
  }

  depends_on = [aws_volume_attachment.data_attachment]
}
