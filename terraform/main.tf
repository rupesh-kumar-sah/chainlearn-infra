# =============================================================================
# ChainLearn Infrastructure - Root Module
# =============================================================================
# This is the root Terraform configuration for ChainLearn.
# Environment-specific configurations are in the environments/ directory.
#
# Usage:
#   cd environments/dev && terraform init && terraform plan
#   cd environments/staging && terraform init && terraform plan
#   cd environments/prod && terraform init && terraform plan
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# This root module is a placeholder. Use the environment-specific
# configurations in the environments/ directory for actual deployments.
# Each environment (dev, staging, prod) has its own:
#   - main.tf      - Module composition
#   - variables.tf - Variable declarations
#   - terraform.tfvars - Environment-specific values
