variable "project_name" {
  description = "Project name — prefixes every resource and tags Project."
  type        = string
}

variable "ssh_public_key" {
  description = "Platform-managed deploy key (SSH_PUBLIC_KEY secret)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size for the application server."
  type        = string
  default     = "t3.medium"
}

variable "db_password" {
  description = "PostgreSQL application role password (DB_PASSWORD secret)."
  type        = string
  sensitive   = true
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB (JVM + Maven cache + Postgres data)."
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for application, nginx and postgres."
  type        = number
  default     = 30
}
