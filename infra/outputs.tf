output "public_ip" {
  description = "Public address of the application server."
  value       = aws_eip.app.public_ip
}

output "instance_id" {
  description = "EC2 instance id of the application server."
  value       = aws_instance.app.id
}

output "app_log_group" {
  description = "CloudWatch log group receiving application logs."
  value       = aws_cloudwatch_log_group.app.name
}

output "nginx_log_group" {
  description = "CloudWatch log group receiving nginx access/error logs."
  value       = aws_cloudwatch_log_group.nginx.name
}

output "postgres_log_group" {
  description = "CloudWatch log group receiving PostgreSQL logs."
  value       = aws_cloudwatch_log_group.postgres.name
}
