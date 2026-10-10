output "elastic_ip" {
  description = "Point an A record for domain_name here (done for you when route53_zone_id is set)."
  value       = aws_eip.n8n.public_ip
}

output "instance_id" {
  description = "Use with: aws ssm start-session --target <instance_id>"
  value       = aws_instance.n8n.id
}

output "backup_bucket" {
  description = "S3 bucket holding the nightly backups under backups/."
  value       = aws_s3_bucket.backups.bucket
}

output "url" {
  description = "n8n URL once DNS resolves and Caddy has its certificate."
  value       = "https://${var.domain_name}"
}
