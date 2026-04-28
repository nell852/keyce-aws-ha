###############################################################
# TP2 – Launch Template, ALB, Auto Scaling Group
###############################################################

resource "tls_private_key" "tp2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "tp2_keypair" {
  key_name   = "${var.project_name}-keypair"
  public_key = tls_private_key.tp2_key.public_key_openssh
}

resource "local_file" "tp2_private_key" {
  content         = tls_private_key.tp2_key.private_key_pem
  filename        = "${path.module}/${var.project_name}-key.pem"
  file_permission = "0400"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.project_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

###############################################################
# LAUNCH TEMPLATE AVEC USER DATA DIRECT
###############################################################
resource "aws_launch_template" "pritunl_lt" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.tp2_keypair.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  # Script d'installation injecté directement pour éviter les erreurs de formatage
  user_data = base64encode(<<-EOF
#!/bin/bash
exec > /var/log/pritunl-install.log 2>&1
set -x

echo "Début de l'installation"
dnf update -y
dnf install -y wget curl gpg --allowerasing

# Pritunl Repo
rpm --import https://raw.githubusercontent.com/pritunl/pgp/master/pritunl_repo_pub.asc
echo "[pritunl]
name=Pritunl Repository
baseurl=https://repo.pritunl.com/stable/yum/oraclelinux/9/
gpgcheck=1
enabled=1" > /etc/yum.repos.d/pritunl.repo

# MongoDB Repo
rpm --import https://www.mongodb.org/static/pgp/server-7.0.asc
echo "[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc" > /etc/yum.repos.d/mongodb-org-7.0.repo

dnf install -y mongodb-org pritunl --allowerasing

systemctl enable --now mongod
systemctl enable --now pritunl

sleep 15
pritunl setup-key > /root/pritunl-setup-key.txt
chmod 600 /root/pritunl-setup-key.txt
echo "Installation terminée"
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "${var.project_name}-pritunl-node" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################
# ALB & ASG
###############################################################
resource "aws_lb" "main_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "pritunl_tg" {
  name     = "${var.project_name}-tg"
  port     = 9700
  protocol = "HTTPS"
  vpc_id   = aws_vpc.main.id
  health_check {
    path     = "/ping"
    protocol = "HTTPS"
    port     = "9700"
    matcher  = "200-399"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.self_signed.arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pritunl_tg.arn
  }
}

resource "aws_autoscaling_group" "pritunl_asg" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  target_group_arns   = [aws_lb_target_group.pritunl_tg.arn]
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  launch_template {
    id      = aws_launch_template.pritunl_lt.id
    version = "$Latest"
  }
}

resource "aws_acm_certificate" "self_signed" {
  private_key      = tls_private_key.tp2_key.private_key_pem
  certificate_body = tls_self_signed_cert.tp2_cert.cert_pem
}

resource "tls_self_signed_cert" "tp2_cert" {
  private_key_pem = tls_private_key.tp2_key.private_key_pem
  subject {
    common_name  = aws_lb.main_alb.dns_name
    organization = "Keyce"
  }
  validity_period_hours = 8760
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}