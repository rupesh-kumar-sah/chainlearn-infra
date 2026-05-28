# =============================================================================
# ChainLearn Compute Module - Variables
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

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs of the private subnets"
  type        = list(string)
}

# Security Groups
variable "api_security_group_id" {
  description = "Security group ID for API service"
  type        = string
}

variable "ai_security_group_id" {
  description = "Security group ID for AI service"
  type        = string
}

variable "indexer_security_group_id" {
  description = "Security group ID for Indexer service"
  type        = string
}

variable "frontend_security_group_id" {
  description = "Security group ID for Frontend service"
  type        = string
}

# ECR
variable "ecr_repository_url" {
  description = "Base URL for ECR repositories"
  type        = string
}

# Image Tags
variable "api_image_tag" {
  description = "Docker image tag for API service"
  type        = string
  default     = "latest"
}

variable "ai_image_tag" {
  description = "Docker image tag for AI service"
  type        = string
  default     = "latest"
}

variable "indexer_image_tag" {
  description = "Docker image tag for Indexer service"
  type        = string
  default     = "latest"
}

variable "frontend_image_tag" {
  description = "Docker image tag for Frontend service"
  type        = string
  default     = "latest"
}

# Resource Allocation
variable "api_cpu" {
  description = "CPU units for API service (1 vCPU = 1024)"
  type        = number
  default     = 512
}

variable "api_memory" {
  description = "Memory (MiB) for API service"
  type        = number
  default     = 1024
}

variable "ai_cpu" {
  description = "CPU units for AI service"
  type        = number
  default     = 1024
}

variable "ai_memory" {
  description = "Memory (MiB) for AI service"
  type        = number
  default     = 2048
}

variable "indexer_cpu" {
  description = "CPU units for Indexer service"
  type        = number
  default     = 256
}

variable "indexer_memory" {
  description = "Memory (MiB) for Indexer service"
  type        = number
  default     = 512
}

variable "frontend_cpu" {
  description = "CPU units for Frontend service"
  type        = number
  default     = 256
}

variable "frontend_memory" {
  description = "Memory (MiB) for Frontend service"
  type        = number
  default     = 512
}

# Desired Counts
variable "api_desired_count" {
  description = "Desired number of API tasks"
  type        = number
  default     = 2
}

variable "ai_desired_count" {
  description = "Desired number of AI tasks"
  type        = number
  default     = 1
}

variable "indexer_desired_count" {
  description = "Desired number of Indexer tasks"
  type        = number
  default     = 1
}

variable "frontend_desired_count" {
  description = "Desired number of Frontend tasks"
  type        = number
  default     = 2
}

# Max Counts (for auto-scaling)
variable "api_max_count" {
  description = "Maximum number of API tasks"
  type        = number
  default     = 10
}

variable "frontend_max_count" {
  description = "Maximum number of Frontend tasks"
  type        = number
  default     = 10
}

# Database/Redis endpoints
variable "database_endpoint" {
  description = "Endpoint for the RDS PostgreSQL database"
  type        = string
}

variable "redis_endpoint" {
  description = "Endpoint for the ElastiCache Redis cluster"
  type        = string
}

# Stellar Configuration
variable "stellar_network" {
  description = "Stellar network (testnet, mainnet)"
  type        = string
  default     = "testnet"
}

variable "stellar_horizon_url" {
  description = "Stellar Horizon server URL"
  type        = string
  default     = "https://horizon-testnet.stellar.org"
}

# URLs
variable "api_public_url" {
  description = "Public URL for the API (used by frontend)"
  type        = string
  default     = ""
}

# ALB
variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS"
  type        = string
}

variable "alb_logs_bucket" {
  description = "S3 bucket for ALB access logs (empty to disable)"
  type        = string
  default     = ""
}

# Logging
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
