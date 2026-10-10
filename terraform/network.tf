# One public subnet is enough for a single instance. The instance has no
# SSH port open: administration is through SSM Session Manager.
resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11:Flow logs add CloudWatch cost for one instance with two open ports; listed under production additions.
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.project_name }
}

# The default security group allows all traffic between its members. Nothing
# uses it, so strip every rule.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = var.project_name }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.20.1.0/24"

  # The instance gets a stable Elastic IP instead of an auto-assigned one.
  map_public_ip_on_launch = false

  tags = { Name = "${var.project_name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.project_name}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "n8n" {
  #checkov:skip=CKV2_AWS_5:Attached to the instance in ec2.tf.
  name        = "${var.project_name}-web"
  description = "HTTPS to Caddy; no SSH"
  vpc_id      = aws_vpc.this.id
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.n8n.id
  description       = "HTTPS to Caddy"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  #checkov:skip=CKV_AWS_260:Port 80 is required for the Let's Encrypt HTTP-01 challenge; Caddy redirects all other HTTP requests to HTTPS.
  security_group_id = aws_security_group.n8n.id
  description       = "ACME HTTP-01 challenge and redirect to HTTPS"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

# Outbound HTTPS only: package repositories, container registries, SSM, S3,
# Let's Encrypt and the APIs n8n workflows call. DNS and NTP go to the
# Amazon-provided resolvers, which security groups do not filter.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.n8n.id
  description       = "Outbound HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
