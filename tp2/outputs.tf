###############################################################
# TP2 – Outputs
###############################################################

output "vpc_id" {
  description = "ID du VPC"
  value       = aws_vpc.main.id
}

output "alb_dns_name" {
  description = "DNS du Load Balancer (accès Pritunl UI)"
  value       = aws_lb.main_alb.dns_name
}

output "pritunl_ui_url" {
  description = "URL de l'interface Pritunl"
  value       = "https://${aws_lb.main_alb.dns_name}"
}

output "rds_endpoint" {
  description = "Endpoint de connexion RDS MySQL"
  value       = aws_db_instance.main_rds.endpoint
  sensitive   = true
}

output "s3_bucket_name" {
  description = "Nom du bucket S3"
  value       = aws_s3_bucket.keyce_bucket.id
}

output "lambda_function_name" {
  description = "Nom de la fonction Lambda"
  value       = aws_lambda_function.log_processor.function_name
}

output "asg_name" {
  description = "Nom de l'Auto Scaling Group"
  value       = aws_autoscaling_group.pritunl_asg.name
}

output "ssh_key_file" {
  description = "Clé SSH privée générée"
  value       = "${var.project_name}-key.pem"
}

output "pritunl_setup_instructions" {
  description = "Instructions de configuration initiale Pritunl"
  value       = <<-INSTRUCTIONS
    === CONFIGURATION INITIALE PRITUNL ===

    1. Récupérer la clé de setup depuis une instance :
       aws ssm start-session --target <instance-id>
       cat /root/pritunl-setup-key.txt

    2. Accéder à l'interface web :
       URL : https://${aws_lb.main_alb.dns_name}

    3. Entrer la setup-key et configurer le mot de passe admin

    4. Créer une organization et un user VPN

    5. Configurer un serveur VPN :
       - Port : 1194 (UDP)
       - Protocole : OpenVPN ou WireGuard

    6. Télécharger le profil client .ovpn

    === COMMANDES UTILES ===
    # Voir les instances ASG :
    aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.pritunl_asg.name}

    # Tester Lambda :
    aws lambda invoke --function-name ${aws_lambda_function.log_processor.function_name} --payload '{}' response.json

    # Uploader un log test vers S3 :
    echo "2024-01-01 Connected user1" > test.log
    aws s3 cp test.log s3://${aws_s3_bucket.keyce_bucket.id}/logs/test.log
  INSTRUCTIONS
}
