###############################################################
# TP2 – RDS MySQL (Multi-AZ)
###############################################################

# Subnet group pour RDS (utilise les subnets privés)
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name    = "${var.project_name}-rds-subnet-group"
    Project = var.project_name
  }
}

# Paramètre group
resource "aws_db_parameter_group" "mysql_params" {
  family = "mysql8.0"
  name   = "${var.project_name}-mysql-params"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = { Project = var.project_name }
}

# Instance RDS MySQL Multi-AZ
resource "aws_db_instance" "main_rds" {
  identifier = "${var.project_name}-mysql"

  # Moteur
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro" # Free tier eligible

  # Stockage
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  # Base et credentials
  db_name  = "keycedb"
  username = var.db_username
  password = var.db_password

  # Réseau
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false

  # HA Multi-AZ
  multi_az = true

  # Paramètres
  parameter_group_name = aws_db_parameter_group.mysql_params.name

  # Maintenance et backup
  backup_retention_period   = 0
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true

  # Protection
  deletion_protection = false # Mettre true en production
  skip_final_snapshot = true  # Mettre false en production

  tags = {
    Name    = "${var.project_name}-rds"
    Project = var.project_name
  }
}
