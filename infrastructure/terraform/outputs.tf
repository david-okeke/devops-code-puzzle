output "app_url" {
  value = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_eip.web.public_ip}"
}

output "instance_public_ip" {
  value = aws_eip.web.public_ip
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}

output "db_secret_name" {
  value = aws_ssm_parameter.db_password.name
}

output "ssm_connect_command" {
  value = "aws ssm start-session --target ${aws_instance.web.id} --region ${var.aws_region}"
}