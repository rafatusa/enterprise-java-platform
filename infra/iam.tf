# Instance role: the application server writes its own logs to CloudWatch and
# reads nothing else. Least privilege per AWS IAM best practices — the log group
# ARNs are scoped to this project, not "*".

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role" "app" {
  name = "${var.project_name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.project_name}-cloudwatch-logs"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.app.arn}:*",
          "${aws_cloudwatch_log_group.nginx.arn}:*",
          "${aws_cloudwatch_log_group.postgres.arn}:*"
        ]
      },
      {
        # The CloudWatch agent reads instance metadata to tag log streams.
        Effect   = "Allow"
        Action   = ["ec2:DescribeTags"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.app.name

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}
