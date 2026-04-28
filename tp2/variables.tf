###############################################################
# TP2 – Variables
###############################################################

variable "aws_region" {
  description = "Région AWS cible"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Préfixe pour toutes les ressources"
  type        = string
  default     = "keyce-tp2"
}

variable "vpc_cidr" {
  description = "CIDR du VPC principal"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs des subnets publics (2 AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs des subnets privés (2 AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "instance_type" {
  description = "Type d'instance EC2 pour Pritunl"
  type        = string
  default     = "t3.small"
}

variable "asg_min_size" {
  description = "Nombre minimum d'instances dans l'ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Nombre maximum d'instances dans l'ASG"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Nombre d'instances désiré dans l'ASG"
  type        = number
  default     = 2
}

variable "db_username" {
  description = "Nom d'utilisateur RDS"
  type        = string
  default     = "keyce_admin"
  sensitive   = true
}

variable "db_password" {
  description = "Mot de passe RDS (à surcharger via TF_VAR ou tfvars)"
  type        = string
  sensitive   = true
  # Ne pas mettre de valeur par défaut pour un mot de passe
}
