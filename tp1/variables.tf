###############################################################
# TP1 – Variables
###############################################################

variable "aws_region" {
  description = "Région AWS cible"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Préfixe utilisé pour nommer toutes les ressources"
  type        = string
  default     = "keyce-tp1"
}
