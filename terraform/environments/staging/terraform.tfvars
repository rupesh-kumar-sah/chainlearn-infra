# =============================================================================
# ChainLearn Staging Environment - Variable Values
# =============================================================================

project_name = "chainlearn"
aws_region   = "us-east-1"

# Networking
vpc_cidr            = "10.1.0.0/16"
private_subnet_cidrs = ["10.1.10.0/24", "10.1.11.0/24"]

# ECR - Update with your AWS account ID
ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com"

# ACM Certificate
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id"

# API URL
api_public_url = "https://api-staging.chainlearn.io"

# Alerts
alert_email_addresses = ["devops@chainlearn.io", "engineering@chainlearn.io"]

# Grafana
grafana_admin_user_ids = []

# Tags
tags = {
  Team      = "chainlearn"
  CostCenter = "staging"
}
