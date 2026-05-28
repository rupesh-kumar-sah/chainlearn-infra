# =============================================================================
# ChainLearn Monitoring Module - Variables
# =============================================================================

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "chainlearn"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# Networking
variable "private_subnet_ids" {
  description = "IDs of the private subnets"
  type        = list(string)
}

variable "grafana_security_group_id" {
  description = "Security group ID for Grafana"
  type        = string
}

# ECS
variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "ecs_service_names" {
  description = "List of ECS service names to monitor"
  type        = list(string)
  default     = []
}

variable "ecs_log_group_name" {
  description = "Name of the ECS CloudWatch log group"
  type        = string
}

# ALB
variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB"
  type        = string
}

# Alerting
variable "alert_email_addresses" {
  description = "Email addresses for CloudWatch alarm notifications"
  type        = list(string)
  default     = []
}

# Grafana
variable "grafana_admin_user_ids" {
  description = "AWS SSO user IDs for Grafana admin access"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
