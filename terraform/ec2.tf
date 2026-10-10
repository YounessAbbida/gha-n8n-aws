data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  # Every file under stack/ is copied to /opt/n8n on first boot.
  stack_files = {
    for f in fileset("${path.module}/../stack", "**") :
    f => filebase64("${path.module}/../stack/${f}")
    if !endswith(f, ".example")
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    aws_region      = var.aws_region
    param_prefix    = local.param_prefix
    domain_name     = var.domain_name
    acme_email      = var.acme_email
    timezone        = var.timezone
    n8n_version     = var.n8n_version
    backup_bucket   = aws_s3_bucket.backups.bucket
    compose_version = var.compose_version
    compose_sha256  = var.compose_sha256
    stack_files     = local.stack_files
  })
}

resource "aws_instance" "n8n" {
  #checkov:skip=CKV_AWS_126:Detailed monitoring adds cost; 5-minute metrics are enough for one instance.
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.n8n.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  ebs_optimized          = true

  # Compressed: the stack files are embedded and must stay under the 16 KB limit.
  user_data_base64 = base64gzip(local.user_data)

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
    # Hop limit 1: the host can reach IMDS, containers cannot.
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_gb
    encrypted             = true
    delete_on_termination = true
  }

  tags = { Name = var.project_name }

  lifecycle {
    # A new AMI or an edited stack file must not silently replace the server.
    # Rebuilds are deliberate: see docs/RUNBOOK.md, "Rebuild from backup".
    ignore_changes = [ami, user_data_base64]
  }
}

resource "aws_eip" "n8n" {
  domain   = "vpc"
  instance = aws_instance.n8n.id

  tags = { Name = var.project_name }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route53_record" "n8n" {
  count = var.route53_zone_id == "" ? 0 : 1

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_eip.n8n.public_ip]
}
