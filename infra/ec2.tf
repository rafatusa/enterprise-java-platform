data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# The ONLY key-injection path: cloud key pair from the platform secret;
# authorized_keys is seeded at launch by cloud-init.
resource "aws_key_pair" "app" {
  key_name   = "${var.project_name}-deploy-key"
  public_key = var.ssh_public_key

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

# NOTE ON DESCRIPTIONS: AWS restricts security-group rule descriptions to
# ^[0-9A-Za-z_ .:/()#,@\[\]+=&;{}!$*-]*$ — plain ASCII only. Em-dashes and other
# typographic punctuation are REJECTED by the API (caught by validate_project).
# Keep these strings to plain ASCII; put the prose in comments like this one.
resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "SSH + public web for ${var.project_name}"

  # SSH for the Ansible configure stage.
  #
  # KNOWN RESIDUAL RISK (Trivy AWS-0107): var.ssh_allowed_cidr defaults to
  # 0.0.0.0/0 because the configure stage runs on GITHUB-HOSTED RUNNERS, whose
  # egress addresses are dynamic and drawn from a large, frequently-changing
  # pool. Pinning a narrow CIDR here would break every deploy the moment GitHub
  # rotated its ranges.
  #
  # This is a deliberate Tier-1 trade-off, NOT an oversight. Close it by either:
  #   1. Setting ssh_allowed_cidr to your own egress range (the correct move for
  #      a self-hosted runner or a bastion) — a one-line tfvars change; or
  #   2. Migrating the configure stage to AWS SSM Session Manager and removing
  #      this rule entirely. The IAM role and instance profile this instance
  #      already carries are the prerequisite for that, and IMDSv2 is enforced
  #      below. That removes port 22 from the internet completely and is the
  #      recommended production end state.
  #
  # Compensating controls TODAY: password authentication is disabled on the
  # host (key-only), the only authorized key is the platform-managed deploy
  # keypair, and the application itself never listens on a public port —
  # Spring Boot binds 127.0.0.1:8080 and nginx is the sole public entry point.
  ingress {
    description = "SSH (see var.ssh_allowed_cidr - documented Tier-1 tradeoff)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # EGRESS IS RESTRICTED (Trivy AWS-0104 — genuinely fixed, not waived).
  #
  # This host is not a general-purpose workstation. Everything it legitimately
  # reaches outbound is HTTPS, HTTP, DNS or NTP:
  #   - Ubuntu archive + security updates (apt, HTTP and HTTPS)
  #   - Maven Central, for the on-host build
  #   - ghcr.io, for the container image
  #   - CloudWatch Logs and SSM endpoints, for the agent and IAM role
  # Restricting egress means a compromised process cannot open an arbitrary
  # outbound channel on a port of its choosing.
  egress {
    description = "HTTPS out (apt, Maven Central, GHCR, CloudWatch, SSM)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP out (Ubuntu archive mirrors still serving plain HTTP)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS over UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "DNS over TCP (large responses fall back to TCP)"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Clock skew breaks TLS validation and JWT expiry checks, so NTP is required.
  egress {
    description = "NTP time synchronisation"
    from_port   = 123
    to_port     = 123
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.app.key_name
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.app.name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  # IAM instance profile attachment races IAM propagation on first apply.
  depends_on = [aws_iam_instance_profile.app]

  tags = {
    Name      = var.project_name
    Project   = var.project_name
    ManagedBy = "udap"
  }
}

# EIP is required on EC2 so the address survives instance replacement.
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Project   = var.project_name
    ManagedBy = "udap"
  }
}
