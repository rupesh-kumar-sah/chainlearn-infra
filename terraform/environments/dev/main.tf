# =============================================================================
# ChainLearn Dev Environment
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "chainlearn-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "chainlearn-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "chainlearn"
      Environment = "dev"
      ManagedBy   = "terraform"
      Repository  = "chainlearn-infra"
    }
  }
}

# -----------------------------------------------------------------------------
# Networking Module
# -----------------------------------------------------------------------------
module "networking" {
  source = "../../modules/networking"

  project_name        = var.project_name
  environment         = "dev"
  vpc_cidr            = var.vpc_cidr
  az_count            = 2
  single_nat_gateway  = true  # Cost saving for dev
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Database Module
# -----------------------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  project_name               = var.project_name
  environment                = "dev"
  private_subnet_ids         = module.networking.private_subnet_ids
  database_security_group_id = module.networking.database_security_group_id
  redis_security_group_id    = module.networking.redis_security_group_id

  # Smaller instances for dev
  db_instance_class  = "db.t3.micro"
  db_allocated_storage = 20
  db_max_allocated_storage = 50

  redis_node_type = "cache.t3.micro"

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Compute Module
# -----------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  project_name        = var.project_name
  environment         = "dev"
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids

  # Security Groups
  api_security_group_id      = module.networking.api_security_group_id
  ai_security_group_id       = module.networking.ai_security_group_id
  indexer_security_group_id  = module.networking.indexer_security_group_id
  frontend_security_group_id = module.networking.frontend_security_group_id

  # ECR
  ecr_repository_url = var.ecr_repository_url

  # Database/Redis endpoints
  database_endpoint = module.database.database_endpoint
  redis_endpoint    = module.database.redis_endpoint

  # Stellar
  stellar_network      = "testnet"
  stellar_horizon_url  = "https://horizon-testnet.stellar.org"

  # URLs
  api_public_url = var.api_public_url

  # ALB
  certificate_arn = var.certificate_arn

  # Resource allocation - smaller for dev
  api_cpu       = 256
  api_memory    = 512
  ai_cpu        = 512
  ai_memory     = 1024
  indexer_cpu   = 256
  indexer_memory = 512
  frontend_cpu  = 256
  frontend_memory = 512

  # Single replica for dev
  api_desired_count      = 1
  ai_desired_count       = 1
  indexer_desired_count  = 1
  frontend_desired_count = 1

  api_max_count      = 2
  frontend_max_count = 2

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Monitoring Module
# -----------------------------------------------------------------------------
module "monitoring" {
  source = "../../modules/monitoring"

  project_name       = var.project_name
  environment        = "dev"
  private_subnet_ids = module.networking.private_subnet_ids

  # ECS
  ecs_cluster_name   = module.compute.ecs_cluster_name
  ecs_service_names  = [
    module.compute.api_service_name,
    module.compute.ai_service_name,
    module.compute.indexer_service_name,
    module.compute.frontend_service_name
  ]
  ecs_log_group_name = module.compute.cloudwatch_log_group_name

  # ALB
  alb_arn_suffix = module.compute.alb_arn

  # Alerting
  alert_email_addresses = var.alert_email_addresses

  # Grafana
  grafana_security_group_id = module.networking.api_security_group_id
  grafana_admin_user_ids    = var.grafana_admin_user_ids

  tags = var.tags
}
