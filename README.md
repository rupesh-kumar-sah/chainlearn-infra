# ChainLearn Infrastructure

Infrastructure-as-code repository for ChainLearn, a Stellar-based AI learning platform.

## Overview

This repository contains all infrastructure configurations for deploying and managing the ChainLearn platform across development, staging, and production environments.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                      │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                              VPC                                     │   │
│  │  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐          │   │
│  │  │   Public      │    │   Private     │    │   Private     │          │   │
│  │  │   Subnets     │    │   Subnets     │    │   Subnets     │          │   │
│  │  │              │    │              │    │              │          │   │
│  │  │  ┌────────┐  │    │  ┌────────┐  │    │  ┌────────┐  │          │   │
│  │  │  │   ALB   │  │    │  │  ECS   │  │    │  │   RDS  │  │          │   │
│  │  │  └────────┘  │    │  │ Cluster│  │    │  │Postgres│  │          │   │
│  │  │              │    │  └────────┘  │    │  └────────┘  │          │   │
│  │  └──────────────┘    │              │    │              │          │   │
│  │                      │  ┌────────┐  │    │  ┌────────┐  │          │   │
│  │                      │  │ElastiC │  │    │  │ Redis  │  │          │   │
│  │                      │  │  ache  │  │    │  └────────┘  │          │   │
│  │                      │  └────────┘  │    └──────────────┘          │   │
│  │                      └──────────────┘                              │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │
│  │ CloudWatch  │  │   Grafana   │  │ Prometheus  │  │    SNS      │      │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| API | 3001 | Main REST API service (Node.js) |
| AI | 8000 | AI/ML service for course generation (Python) |
| Indexer | 3002 | Stellar blockchain indexer (Node.js) |
| Frontend | 3000 | Next.js web application |

## Directory Structure

```
chainlearn-infra/
├── terraform/                 # Infrastructure as Code
│   ├── modules/               # Reusable Terraform modules
│   │   ├── networking/        # VPC, subnets, security groups
│   │   ├── compute/           # ECS Fargate services
│   │   ├── database/          # RDS PostgreSQL, ElastiCache Redis
│   │   └── monitoring/        # CloudWatch, Grafana, Prometheus
│   ├── environments/          # Environment-specific configs
│   │   ├── dev/               # Development environment
│   │   ├── staging/           # Staging environment
│   │   └── prod/              # Production environment
│   └── main.tf                # Root module
│
├── kubernetes/                # Kubernetes manifests
│   ├── base/                  # Base Kustomize resources
│   │   ├── api-deployment.yml
│   │   ├── ai-deployment.yml
│   │   ├── indexer-deployment.yml
│   │   ├── frontend-deployment.yml
│   │   ├── ingress.yml
│   │   └── namespace.yml
│   └── overlays/              # Environment overlays
│       ├── dev/
│       ├── staging/
│       └── prod/
│
├── docker/                    # Docker configurations
│   ├── docker-compose.dev.yml # Local development stack
│   └── docker-compose.prod.yml # Production-like local stack
│
├── scripts/                   # Utility scripts
│   ├── setup-stellar-testnet.sh
│   ├── rotate-secrets.sh
│   └── backup-db.sh
│
└── monitoring/                # Monitoring configurations
    ├── grafana/dashboards/    # Grafana dashboard definitions
    └── prometheus/            # Prometheus configuration
```

## Prerequisites

### Required Tools

- **Terraform** >= 1.5.0
- **AWS CLI** >= 2.0
- **kubectl** >= 1.28
- **Docker** >= 24.0
- **kustomize** >= 5.0
- **Node.js** >= 18 (for Stellar SDK)
- **Stellar CLI** (for Soroban contracts)
- **Soroban CLI** (for contract deployment)

### AWS Account Setup

1. Create an IAM user with appropriate permissions
2. Configure AWS CLI:
   ```bash
   aws configure
   ```
3. Create S3 bucket for Terraform state:
   ```bash
   aws s3api create-bucket \
     --bucket chainlearn-terraform-state \
     --region us-east-1
   ```
4. Create DynamoDB table for state locking:
   ```bash
   aws dynamodb create-table \
     --table-name chainlearn-terraform-locks \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST
   ```

## Quick Start

### Local Development

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-org/chainlearn-infra.git
   cd chainlearn-infra
   ```

2. **Set up Stellar testnet accounts:**
   ```bash
   ./scripts/setup-stellar-testnet.sh testnet
   ```

3. **Start the local development stack:**
   ```bash
   cd docker
   cp .env.example .env  # Edit with your values
   docker compose -f docker-compose.dev.yml up -d
   ```

4. **Access the services:**
   - Frontend: http://localhost:3000
   - API: http://localhost:3001
   - AI: http://localhost:8000
   - Indexer: http://localhost:3002
   - Adminer (DB): http://localhost:8080
   - Mailhog: http://localhost:8025

### Deploy to AWS (Dev)

1. **Initialize Terraform:**
   ```bash
   cd terraform/environments/dev
   terraform init
   ```

2. **Review the plan:**
   ```bash
   terraform plan
   ```

3. **Apply the configuration:**
   ```bash
   terraform apply
   ```

4. **Configure kubectl:**
   ```bash
   aws eks update-kubeconfig \
     --region us-east-1 \
     --name chainlearn-dev
   ```

5. **Deploy to Kubernetes:**
   ```bash
   kubectl apply -k kubernetes/overlays/dev/
   ```

## Environments

### Development

- Single NAT gateway (cost saving)
- Smaller instance sizes
- Single replicas for services
- Testnet Stellar network
- Debug logging enabled

### Staging

- Single NAT gateway
- Medium instance sizes
- 2 replicas for critical services
- Testnet Stellar network
- Info logging

### Production

- NAT gateway per AZ (high availability)
- Large instance sizes
- 3 replicas for critical services
- Mainnet Stellar network
- Warning-level logging
- Multi-AZ RDS
- Redis cluster with failover

## Terraform Modules

### Networking Module

Creates the VPC infrastructure:
- VPC with configurable CIDR
- Public and private subnets across multiple AZs
- Internet gateway and NAT gateways
- Security groups for all services
- VPC flow logs

```hcl
module "networking" {
  source = "../../modules/networking"

  project_name = "chainlearn"
  environment  = "dev"
  vpc_cidr     = "10.0.0.0/16"
  az_count     = 2
}
```

### Compute Module

Manages ECS Fargate services:
- ECS cluster with Fargate capacity providers
- Task definitions for API, AI, Indexer, Frontend
- Application Load Balancer
- Service discovery
- Auto-scaling policies

```hcl
module "compute" {
  source = "../../modules/compute"

  project_name       = "chainlearn"
  environment        = "dev"
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  # ... other variables
}
```

### Database Module

Provisions database infrastructure:
- RDS PostgreSQL with encryption
- ElastiCache Redis cluster
- Automated backups
- Performance Insights
- CloudWatch alarms

```hcl
module "database" {
  source = "../../modules/database"

  project_name       = "chainlearn"
  environment        = "dev"
  private_subnet_ids = module.networking.private_subnet_ids
  # ... other variables
}
```

### Monitoring Module

Sets up observability:
- CloudWatch dashboards
- Grafana workspace (Amazon Managed Grafana)
- Prometheus workspace (Amazon Managed Service for Prometheus)
- SNS alerts
- Log metric filters

```hcl
module "monitoring" {
  source = "../../modules/monitoring"

  project_name       = "chainlearn"
  environment        = "dev"
  ecs_cluster_name   = module.compute.ecs_cluster_name
  # ... other variables
}
```

## Kubernetes

### Base Resources

The base Kubernetes manifests define:
- Deployments with 2 replicas, resource limits, health checks
- Services (ClusterIP for internal, LoadBalancer for frontend)
- Ingress with TLS termination and rate limiting
- PodDisruptionBudgets for high availability
- ServiceAccounts

### Kustomize Overlays

Each environment has a kustomization overlay that:
- Adjusts replica counts
- Modifies resource limits
- Changes environment-specific configurations
- Updates domain names and TLS certificates

**Apply an overlay:**
```bash
# Development
kubectl apply -k kubernetes/overlays/dev/

# Staging
kubectl apply -k kubernetes/overlays/staging/

# Production
kubectl apply -k kubernetes/overlays/prod/
```

## Scripts

### Stellar Testnet Setup

Sets up Stellar testnet accounts and deploys Soroban contracts:

```bash
./scripts/setup-stellar-testnet.sh [network]

# Examples:
./scripts/setup-stellar-testnet.sh testnet
./scripts/setup-stellar-testnet.sh standalone
```

### Secret Rotation

Rotates secrets in AWS Secrets Manager and updates Kubernetes:

```bash
./scripts/rotate-secrets.sh [environment] [secret-name]

# Examples:
./scripts/rotate-secrets.sh dev all
./scripts/rotate-secrets.sh prod database
./scripts/rotate-secrets.sh staging redis
```

### Database Backup

Backs up PostgreSQL to S3 with encryption:

```bash
./scripts/backup-db.sh [environment]

# Examples:
./scripts/backup-db.sh dev
./scripts/backup-db.sh prod
```

**Cron job (daily at 2 AM):**
```bash
0 2 * * * /path/to/chainlearn-infra/scripts/backup-db.sh prod >> /var/log/chainlearn-backup.log 2>&1
```

## Monitoring

### Grafana Dashboards

Two pre-configured dashboards:

1. **API Metrics** (`api-metrics.json`):
   - Request rate and latency
   - Error rates by status code
   - CPU and memory usage
   - Stellar contract calls
   - Course completions

2. **Contract Metrics** (`contract-metrics.json`):
   - Contract call rates by function
   - Contract latency percentiles
   - Rewards distributed
   - Achievements unlocked
   - Indexer metrics

### Prometheus

Prometheus is configured to scrape metrics from:
- All ChainLearn services
- Node exporter (host metrics)
- Redis exporter
- PostgreSQL exporter
- Blackbox exporter (endpoint monitoring)

### CloudWatch Alarms

Pre-configured alarms for:
- API 5xx errors
- High API latency
- ECS CPU utilization
- Database CPU and storage
- Redis CPU and memory
- Error rate spikes

## Security

### Network Security

- Private subnets for all services
- Security groups with minimal required access
- NAT gateways for outbound internet access
- VPC flow logs enabled

### Data Security

- RDS encryption at rest
- ElastiCache encryption at rest and in transit
- Secrets stored in AWS Secrets Manager
- TLS for all external endpoints

### Access Control

- IAM roles with least privilege
- Kubernetes RBAC
- Service accounts per deployment
- No hardcoded credentials

## Cost Optimization

### Development

- Single NAT gateway
- Smaller instance sizes (t3.micro/small)
- Single replicas
- Shorter log retention (30 days)

### Production

- NAT gateway per AZ (high availability)
- Right-sized instances
- Auto-scaling enabled
- Reserved instances for predictable workloads
- S3 lifecycle policies for backups

## Troubleshooting

### Common Issues

**Terraform state lock:**
```bash
terraform force-unlock <lock-id>
```

**ECS service not starting:**
```bash
aws ecs describe-services \
  --cluster chainlearn-dev \
  --services chainlearn-api

aws logs get-log-events \
  --log-group-name /ecs/chainlearn-dev \
  --log-stream-name api/<task-id>
```

**Kubernetes pod CrashLoopBackOff:**
```bash
kubectl logs -n chainlearn-dev -l app.kubernetes.io/name=chainlearn-api --previous
kubectl describe pod -n chainlearn-dev <pod-name>
```

**Database connection issues:**
```bash
# Check RDS status
aws rds describe-db-instances \
  --db-instance-identifier chainlearn-dev

# Test connection
psql -h <endpoint> -U chainlearn_admin -d chainlearn
```

## Contributing

1. Create a feature branch from `main`
2. Make your changes
3. Test locally with `docker compose`
4. Submit a pull request
5. Wait for CI/CD pipeline to pass

## License

Proprietary - ChainLearn Team

## Support

For infrastructure issues, contact the DevOps team:
- Email: devops@chainlearn.io
- Slack: #chainlearn-infra
