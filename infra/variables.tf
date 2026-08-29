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

# Narrow this and port 22 stops being world-reachable. It defaults open because
# the Ansible configure stage runs on GitHub-hosted runners, whose egress
# addresses are dynamic — see the long note on the SSH ingress rule in
# infra/ec2.tf for the two ways to close it properly (own CIDR, or SSM Session
# Manager). Set it in infra/udap.auto.tfvars or via TF_VAR_ssh_allowed_cidr.
variable "ssh_allowed_cidr" {
  description = "CIDR permitted to reach port 22. Narrow this in any environment where the deploy runner has a stable egress address."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr, 0))
    error_message = "ssh_allowed_cidr must be a valid CIDR block, e.g. 203.0.113.0/24."
  }
}
