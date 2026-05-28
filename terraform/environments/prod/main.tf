# =============================================================================
# ChainLearn Production Environment
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
    key            = "prod/terraform.tfstate"
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
      Environment = "prod"
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
  environment         = "prod"
  vpc_cidr            = var.vpc_cidr
  az_count            = 3  # 3 AZs for production HA
  single_nat_gateway  = false  # NAT per AZ for HA
  private_subnet_cidrs = var.private_subnet_cidrs

  flow_log_retention_days = 90

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Database Module
# -----------------------------------------------------------------------------
module "database" {
  source = "../../modules/database"

  project_name               = var.project_name
  environment                = "prod"
  private_subnet_ids         = module.networking.private_subnet_ids
  database_security_group_id = module.networking.database_security_group_id
  redis_security_group_id    = module.networking.redis_security_group_id

  # Production-grade instances
  db_instance_class      = "db.r6g.large"
  db_replica_instance_class = "db.r6g.large"
  db_allocated_storage   = 100
  db_max_allocated_storage = 500

  redis_node_type = "cache.r6g.large"

  sns_alert_topic_arn = module.monitoring.sns_alert_topic_arn

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Compute Module
# -----------------------------------------------------------------------------
module "compute" {
  source = "../../modules/compute"

  project_name        = var.project_name
  environment         = "prod"
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

  stellar_network      = "mainnet"
  stellar_horizon_url  = "https://horizon.stellar.org"

  api_public_url = var.api_public_url

  certificate_arn = var.certificate_arn
  alb_logs_bucket = var.alb_logs_bucket

  # Production-grade resources
  api_cpu       = 1024
  api_memory    = 2048
  ai_cpu        = 2048
  ai_memory     = 4096
  indexer_cpu   = 512
  indexer_memory = 1024
  frontend_cpu  = 512
  frontend_memory = 1024

  # Multiple replicas for production
  api_desired_count      = 3
  ai_desired_count       = 2
  indexer_desired_count  = 2
  frontend_desired_count = 3

  api_max_count      = 20
  frontend_max_count = 20

  log_retention_days = 90

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Monitoring Module
# -----------------------------------------------------------------------------
module "monitoring" {
  source = "../../modules/monitoring"

  project_name       = var.project_name
  environment        = "prod"
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

  alert_email_addresses     = var.alert_email_addresses
  grafana_security_group_id = module.networking.api_security_group_id
  grafana_admin_user_ids    = var.grafana_admin_user_ids

  log_retention_days = 90

  tags = var.tags
}
