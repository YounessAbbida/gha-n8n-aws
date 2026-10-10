variable "aws_region" {
  description = "AWS region for the instance and the backup bucket."
  type        = string
  default     = "eu-west-3"
}

variable "project_name" {
  description = "Prefix for resource names and the SSM parameter path."
  type        = string
  default     = "n8n"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "domain_name" {
  description = "Public hostname for n8n, for example n8n.example.com. Caddy requests a Let's Encrypt certificate for it."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a lowercase fully qualified hostname."
  }
}

variable "route53_zone_id" {
  description = "Optional Route 53 hosted zone ID. When set, an A record for domain_name is created; otherwise point DNS at the elastic_ip output yourself."
  type        = string
  default     = ""
}

variable "acme_email" {
  description = "Email given to Let's Encrypt for certificate expiry notices."
  type        = string
}

variable "budget_email" {
  description = "Email that receives the monthly budget alerts."
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly budget in USD. Alerts at 80% actual and 100% forecasted."
  type        = number
  default     = 25
}

variable "instance_type" {
  description = "Graviton (arm64) instance type. 2 GB of memory is the practical minimum for n8n plus Postgres."
  type        = string
  default     = "t4g.small"

  validation {
    condition     = can(regex("^[a-z][0-9]+g[a-z]*\\.", var.instance_type))
    error_message = "instance_type must be a Graviton (arm64) type such as t4g.small; the bootstrap installs arm64 binaries."
  }
}

variable "root_volume_gb" {
  description = "Size of the encrypted gp3 root volume, which holds Docker images, Postgres and the n8n data directory."
  type        = number
  default     = 20
}

variable "n8n_version" {
  description = "n8n image tag installed on first boot. Later upgrades use stack/scripts/upgrade.sh, not Terraform."
  type        = string
  default     = "2.42.6"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.n8n_version))
    error_message = "n8n_version must be an exact version such as 2.42.6, never latest."
  }
}

variable "timezone" {
  description = "Timezone for n8n schedules (GENERIC_TIMEZONE)."
  type        = string
  default     = "Europe/Paris"
}

variable "backup_retention_days" {
  description = "Days a nightly backup is kept in S3 before it expires."
  type        = number
  default     = 30
}

variable "compose_version" {
  description = "Docker Compose plugin release installed on the instance."
  type        = string
  default     = "v5.6.0"
}

variable "compose_sha256" {
  description = "SHA-256 of docker-compose-linux-aarch64 for compose_version, from the release's .sha256 file. The download is refused if it does not match."
  type        = string
  default     = "733ec76717ceb59052a9609b9dadfb523b2df8eab57a54212872d10a58078ea2"
}
