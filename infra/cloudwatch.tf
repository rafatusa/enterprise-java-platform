# Log groups are created by terraform (not by the agent) so retention is
# managed as code and teardown removes them cleanly.

resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/application"
  retention_in_days = var.log_retention_days

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/${var.project_name}/nginx"
  retention_in_days = var.log_retention_days

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/${var.project_name}/postgresql"
  retention_in_days = var.log_retention_days

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}
