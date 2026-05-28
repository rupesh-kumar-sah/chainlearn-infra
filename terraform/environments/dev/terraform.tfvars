# =============================================================================
# ChainLearn Dev Environment - Variable Values
# =============================================================================

project_name = "chainlearn"
aws_region   = "us-east-1"

# Networking
vpc_cidr            = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

# ECR - Update with your AWS account ID
ecr_repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com"

# ACM Certificate - Update with your certificate ARN
certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/your-cert-id"

# API URL
api_public_url = "https://api-dev.chainlearn.io"

# Alerts - Update with your email
alert_email_addresses = ["devops@chainlearn.io"]

# Grafana - Update with your SSO user IDs
grafana_admin_user_ids = []

# Tags
tags = {
  Team      = "chainlearn"
  CostCenter = "development"
}
