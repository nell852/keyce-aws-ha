###############################################################
# TP1 – Outputs
###############################################################

output "instance_id" {
  description = "ID de l'instance EC2"
  value       = aws_instance.tp1_instance.id
}

output "instance_public_ip" {
  description = "IP publique Elastic de l'instance"
  value       = aws_eip.tp1_eip.public_ip
}

output "ssh_command" {
  description = "Commande SSH pour se connecter à l'instance"
  value       = "ssh -i ${var.project_name}-key.pem ec2-user@${aws_eip.tp1_eip.public_ip}"
}

output "web_url" {
  description = "URL de la page web Apache"
  value       = "http://${aws_eip.tp1_eip.public_ip}"
}

output "ebs_volume_id" {
  description = "ID du volume EBS supplémentaire"
  value       = aws_ebs_volume.data_volume.id
}

output "snapshot_id" {
  description = "ID du snapshot du volume racine"
  value       = aws_ebs_snapshot.root_snapshot.id
}

output "custom_ami_id" {
  description = "ID de l'AMI personnalisée créée"
  value       = aws_ami_from_instance.keyce_ami.id
}

output "my_detected_ip" {
  description = "IP publique détectée automatiquement (autorisée en SSH)"
  value       = local.my_ip
}

output "mount_instructions" {
  description = "Commandes pour formater et monter le volume EBS /data"
  value       = <<-INSTRUCTIONS
    # Après connexion SSH, exécuter ces commandes :
    sudo mkfs.ext4 /dev/xvdf
    sudo mkdir -p /data
    sudo mount /dev/xvdf /data
    echo '/dev/xvdf /data ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
    df -h /data
  INSTRUCTIONS
}
