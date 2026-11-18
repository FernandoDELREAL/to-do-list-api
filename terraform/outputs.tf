output "ec2_public_ip" {
  description = "IP publica de la EC2"
  value       = aws_instance.app.public_ip
}

output "app_url" {
  description = "URL base de la API"
  value       = "http://${aws_instance.app.public_ip}:8000"
}

output "ec2_instance_id" {
  value = aws_instance.app.id
}

output "rds_endpoint" {
  description = "Endpoint de RDS (solo accesible desde la EC2)"
  value       = aws_db_instance.todo.address
}

output "db_secret_name" {
  description = "Nombre del secret en Secrets Manager"
  value       = aws_secretsmanager_secret.db.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dashboard_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.todo.dashboard_name}"
}
