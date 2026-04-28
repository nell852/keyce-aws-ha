###############################################################
# TP2 – Security Groups
###############################################################

# SG pour le Load Balancer (ALB)
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Trafic HTTP/HTTPS entrant vers ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP public"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS public"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-alb-sg"
    Project = var.project_name
  }
}

# SG pour les instances EC2 (Pritunl)
resource "aws_security_group" "ec2_sg" {
  name        = "${var.project_name}-ec2-sg"
  description = "Trafic vers les instances EC2 Pritunl"
  vpc_id      = aws_vpc.main.id

  # HTTP depuis l'ALB uniquement
  ingress {
    description     = "HTTP depuis ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # HTTPS depuis l'ALB uniquement
  ingress {
    description     = "HTTPS depuis ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Pritunl interface web (depuis ALB)
  ingress {
    description     = "Pritunl UI depuis ALB"
    from_port       = 9700
    to_port         = 9700
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # OpenVPN UDP (Pritunl) – depuis internet directement
  ingress {
    description = "OpenVPN UDP Pritunl"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # WireGuard (Pritunl) – depuis internet
  ingress {
    description = "WireGuard UDP Pritunl"
    from_port   = 51820
    to_port     = 51820
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH depuis l'IP admin uniquement
  ingress {
    description = "SSH admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-ec2-sg"
    Project = var.project_name
  }
}

# SG pour RDS
resource "aws_security_group" "rds_sg" {
  name        = "${var.project_name}-rds-sg"
  description = "Acces MySQL depuis les instances EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL depuis EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-rds-sg"
    Project = var.project_name
  }
}

# SG pour Lambda
resource "aws_security_group" "lambda_sg" {
  name        = "${var.project_name}-lambda-sg"
  description = "SG pour la fonction Lambda dans VPC"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-lambda-sg"
    Project = var.project_name
  }
}
