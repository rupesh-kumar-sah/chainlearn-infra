# =============================================================================
# ChainLearn Staging Environment - Variables
# =============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "chainlearn"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.11.0/24"]
}

variable "ecr_repository_url" {
  description = "Base URL for ECR repositories"
  type        = string
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS"
  type        = string
}

variable "api_public_url" {
  description = "Public URL for the API"
  type        = string
  default     = ""
}

variable "alert_email_addresses" {
  description = "Email addresses for alerts"
  type        = list(string)
  default     = []
}

variable "grafana_admin_user_ids" {
  description = "AWS SSO user IDs for Grafana admin"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
