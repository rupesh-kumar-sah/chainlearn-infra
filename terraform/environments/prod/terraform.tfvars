# =============================================================================
# ChainLearn Production Environment - Variable Values
# =============================================================================

project_name = "chainlearn"
aws_region   = "us-east-1"

# Networking - 3 AZs for production
vpc_cidr            = "10.2.0.0/16"
private_subnet_cidrs = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]

# ECR - Update with your AWS account ID
ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com"

# ACM Certificate - Production certificate
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/your-prod-cert-id"

# ALB Logs
alb_logs_bucket = "chainlearn-alb-logs-prod"

# API URL
api_public_url = "https://api.chainlearn.io"

# Alerts - Production team
alert_email_addresses = [
  "devops@chainlearn.io",
  "engineering@chainlearn.io",
  "oncall@chainlearn.io"
]

# Grafana
grafana_admin_user_ids = []

# Tags
tags = {
  Team       = "chainlearn"
  CostCenter = "production"
  Compliance = "required"
}
