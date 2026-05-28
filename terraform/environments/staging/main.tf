# =============================================================================
# ChainLearn Staging Environment
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
    key            = "staging/terraform.tfstate"
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
      Environment = "staging"
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
  environment         = "staging"
  vpc_cidr            = var.vpc_cidr
  az_count            = 2
  single_nat_gateway  = true  # Single NAT for staging
  private_subnet_cidrs = var.private_subnet_cidrs

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Database Module
# -----------------------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  project_name               = var.project_name
  environment                = "staging"
  private_subnet_ids         = module.networking.private_subnet_ids
  database_security_group_id = module.networking.database_security_group_id
  redis_security_group_id    = module.networking.redis_security_group_id

  # Medium instances for staging
  db_instance_class    = "db.t3.medium"
  db_allocated_storage = 50
  db_max_allocated_storage = 100

  redis_node_type = "cache.t3.medium"

  sns_alert_topic_arn = module.monitoring.sns_alert_topic_arn

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Compute Module
# -----------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  project_name        = var.project_name
  environment         = "staging"
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids

  api_security_group_id      = module.networking.api_security_group_id
  ai_security_group_id       = module.networking.ai_security_group_id
  indexer_security_group_id  = module.networking.indexer_security_group_id
  frontend_security_group_id = module.networking.frontend_security_group_id

  ecr_repository_url = var.ecr_repository_url

  database_endpoint = module.database.database_endpoint
  redis_endpoint    = module.database.redis_endpoint

  stellar_network      = "testnet"
  stellar_horizon_url  = "https://horizon-testnet.stellar.org"

  api_public_url = var.api_public_url

  certificate_arn = var.certificate_arn

  # Medium allocation for staging
  api_cpu       = 512
  api_memory    = 1024
  ai_cpu        = 1024
  ai_memory     = 2048
  indexer_cpu   = 256
  indexer_memory = 512
  frontend_cpu  = 256
  frontend_memory = 512

  # 2 replicas for staging
  api_desired_count      = 2
  ai_desired_count       = 1
  indexer_desired_count  = 1
  frontend_desired_count = 2

  api_max_count      = 5
  frontend_max_count = 5

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Monitoring Module
# -----------------------------------------------------------------------------
module "monitoring" {
  source = "../../modules/monitoring"

  project_name       = var.project_name
  environment        = "staging"
  private_subnet_ids = module.networking.private_subnet_ids

  ecs_cluster_name  = module.compute.ecs_cluster_name
  ecs_service_names = [
    module.compute.api_service_name,
    module.compute.ai_service_name,
    module.compute.indexer_service_name,
    module.compute.frontend_service_name
  ]
  ecs_log_group_name = module.compute.cloudwatch_log_group_name

  alb_arn_suffix = module.compute.alb_arn

  alert_email_addresses  = var.alert_email_addresses
  grafana_security_group_id = module.networking.api_security_group_id
  grafana_admin_user_ids    = var.grafana_admin_user_ids

  tags = var.tags
}
