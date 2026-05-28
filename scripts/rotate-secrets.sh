#!/bin/bash
# =============================================================================
# ChainLearn Secret Rotation Script
# Rotates secrets in AWS Secrets Manager and updates Kubernetes secrets
# =============================================================================
# Prerequisites:
#   - AWS CLI configured with appropriate permissions
#   - kubectl configured with cluster access
#   - jq installed
#
# Usage:
#   ./scripts/rotate-secrets.sh [environment] [secret-name]
#   ./scripts/rotate-secrets.sh dev all
#   ./scripts/rotate-secrets.sh prod database
#   ./scripts/rotate-secrets.sh staging redis
# =============================================================================

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-dev}"
SECRET_NAME="${2:-all}"
PROJECT_NAME="chainlearn"
AWS_REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${PROJECT_NAME}-${ENVIRONMENT}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# -----------------------------------------------------------------------------
# Generate Random Password
# -----------------------------------------------------------------------------
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9!@#$%^&*' | head -c "${length}"
}

# -----------------------------------------------------------------------------
# Rotate Database Password
# -----------------------------------------------------------------------------
rotate_database_secret() {
    log_info "Rotating database secret..."

    local secret_name="${PROJECT_NAME}-${ENVIRONMENT}-db-master"
    local new_password
    new_password=$(generate_password 32)

    # Get current secret
    local current_secret
    current_secret=$(aws secretsmanager get-secret-value \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --query 'SecretString' \
        --output text 2>/dev/null || echo "{}")

    # Parse current values
    local username host port dbname
    username=$(echo "${current_secret}" | jq -r '.username // "chainlearn_admin"')
    host=$(echo "${current_secret}" | jq -r '.host // ""')
    port=$(echo "${current_secret}" | jq -r '.port // "5432"')
    dbname=$(echo "${current_secret}" | jq -r '.dbname // "chainlearn"')

    # Update secret in AWS
    aws secretsmanager update-secret \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --secret-string "$(jq -n \
            --arg username "${username}" \
            --arg password "${new_password}" \
            --arg host "${host}" \
            --arg port "${port}" \
            --arg dbname "${dbname}" \
            '{username: $username, password: $password, host: $host, port: $port, dbname: $dbname, engine: "postgres"}')" \
        --output text

    # Update RDS password
    log_info "Updating RDS password..."
    aws rds modify-db-instance \
        --db-instance-identifier "${PROJECT_NAME}-${ENVIRONMENT}" \
        --master-user-password "${new_password}" \
        --apply-immediately \
        --region "${AWS_REGION}" \
        --output text

    # Update Kubernetes secret
    update_kubernetes_secret "database-url" \
        "postgresql://${username}:${new_password}@${host}:${port}/${dbname}"

    log_success "Database secret rotated"
}

# -----------------------------------------------------------------------------
# Rotate Redis Auth Token
# -----------------------------------------------------------------------------
rotate_redis_secret() {
    log_info "Rotating Redis secret..."

    local secret_name="${PROJECT_NAME}-${ENVIRONMENT}-redis-auth"
    local new_token
    new_token=$(generate_password 64)

    # Get current secret
    local current_secret
    current_secret=$(aws secretsmanager get-secret-value \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --query 'SecretString' \
        --output text 2>/dev/null || echo "{}")

    local host
    host=$(echo "${current_secret}" | jq -r '.host // ""')

    # Update secret in AWS
    aws secretsmanager update-secret \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --secret-string "$(jq -n \
            --arg auth_token "${new_token}" \
            --arg host "${host}" \
            --arg port "6379" \
            '{auth_token: $auth_token, host: $host, port: $port}')" \
        --output text

    # Update ElastiCache auth token
    log_info "Updating ElastiCache auth token..."
    aws elasticache modify-replication-group \
        --replication-group-id "${PROJECT_NAME}-${ENVIRONMENT}" \
        --auth-token "${new_token}" \
        --apply-immediately \
        --region "${AWS_REGION}" \
        --output text 2>/dev/null || log_warn "Failed to update ElastiCache directly. Update manually if needed."

    # Update Kubernetes secret
    update_kubernetes_secret "redis-url" \
        "redis://:${new_token}@${host}:6379"

    log_success "Redis secret rotated"
}

# -----------------------------------------------------------------------------
# Rotate JWT Secret
# -----------------------------------------------------------------------------
rotate_jwt_secret() {
    log_info "Rotating JWT secret..."

    local secret_name="${PROJECT_NAME}-${ENVIRONMENT}-jwt-secret"
    local new_secret
    new_secret=$(generate_password 64)

    # Update secret in AWS
    aws secretsmanager put-secret-value \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --secret-string "${new_secret}" \
        --output text 2>/dev/null || {
        aws secretsmanager create-secret \
            --name "${secret_name}" \
            --region "${AWS_REGION}" \
            --secret-string "${new_secret}" \
            --output text
    }

    # Update Kubernetes secret
    update_kubernetes_secret "jwt-secret" "${new_secret}"

    log_success "JWT secret rotated"
}

# -----------------------------------------------------------------------------
# Rotate Stellar Secret Key
# -----------------------------------------------------------------------------
rotate_stellar_secret() {
    log_info "Rotating Stellar secret key..."

    local secret_name="${PROJECT_NAME}-${ENVIRONMENT}-stellar-secret"
    local new_secret
    new_secret=$(generate_password 64)

    # Update secret in AWS
    aws secretsmanager put-secret-value \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --secret-string "${new_secret}" \
        --output text 2>/dev/null || {
        aws secretsmanager create-secret \
            --name "${secret_name}" \
            --region "${AWS_REGION}" \
            --secret-string "${new_secret}" \
            --output text
    }

    # Update Kubernetes secret
    update_kubernetes_secret "stellar-secret-key" "${new_secret}"

    log_success "Stellar secret rotated"
    log_warn "Note: You may need to update the Stellar key in your contract configuration"
}

# -----------------------------------------------------------------------------
# Rotate OpenAI API Key
# -----------------------------------------------------------------------------
rotate_openai_secret() {
    log_info "Rotating OpenAI API key..."
    log_warn "OpenAI API keys must be rotated manually in the OpenAI dashboard"
    log_warn "After rotation, update the secret in AWS Secrets Manager"

    read -p "Enter new OpenAI API key (or press Enter to skip): " new_key

    if [ -n "${new_key}" ]; then
        local secret_name="${PROJECT_NAME}-${ENVIRONMENT}-openai-api-key"

        aws secretsmanager put-secret-value \
            --secret-id "${secret_name}" \
            --region "${AWS_REGION}" \
            --secret-string "${new_key}" \
            --output text 2>/dev/null || {
            aws secretsmanager create-secret \
                --name "${secret_name}" \
                --region "${AWS_REGION}" \
                --secret-string "${new_key}" \
                --output text
        }

        # Update Kubernetes secret
        update_kubernetes_secret "openai-api-key" "${new_key}"

        log_success "OpenAI API key updated"
    else
        log_warn "Skipping OpenAI API key rotation"
    fi
}

# -----------------------------------------------------------------------------
# Update Kubernetes Secret
# -----------------------------------------------------------------------------
update_kubernetes_secret() {
    local key="$1"
    local value="$2"
    local secret_name="chainlearn-secrets"

    log_info "Updating Kubernetes secret: ${key}"

    # Check if namespace exists
    if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
        log_warn "Namespace ${NAMESPACE} does not exist. Creating..."
        kubectl create namespace "${NAMESPACE}"
    fi

    # Create or update secret
    kubectl create secret generic "${secret_name}" \
        --namespace "${NAMESPACE}" \
        --from-literal="${key}=${value}" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_success "Kubernetes secret updated: ${key}"
}

# -----------------------------------------------------------------------------
# Restart Deployments
# -----------------------------------------------------------------------------
restart_deployments() {
    log_info "Restarting deployments to pick up new secrets..."

    local deployments=("chainlearn-api" "chainlearn-ai" "chainlearn-indexer")

    for deploy in "${deployments[@]}"; do
        if kubectl get deployment "${deploy}" -n "${NAMESPACE}" &>/dev/null; then
            kubectl rollout restart deployment/"${deploy}" -n "${NAMESPACE}"
            log_info "Restarted ${deploy}"
        fi
    done

    # Wait for rollouts
    for deploy in "${deployments[@]}"; do
        if kubectl get deployment "${deploy}" -n "${NAMESPACE}" &>/dev/null; then
            kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}" --timeout=300s || true
        fi
    done

    log_success "Deployments restarted"
}

# -----------------------------------------------------------------------------
# Print Summary
# -----------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "============================================="
    echo "  Secret Rotation Complete"
    echo "============================================="
    echo ""
    echo "Environment: ${ENVIRONMENT}"
    echo "Secret Rotated: ${SECRET_NAME}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify services are running: kubectl get pods -n ${NAMESPACE}"
    echo "  2. Check logs for any errors: kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/part-of=chainlearn"
    echo "  3. Test the application endpoints"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "============================================="
    echo "  ChainLearn Secret Rotation"
    echo "============================================="
    echo ""
    echo "Environment: ${ENVIRONMENT}"
    echo "Secret: ${SECRET_NAME}"
    echo ""

    read -p "Are you sure you want to rotate secrets? (yes/no): " confirm
    if [ "${confirm}" != "yes" ]; then
        log_info "Aborted."
        exit 0
    fi

    case "${SECRET_NAME}" in
        database)
            rotate_database_secret
            ;;
        redis)
            rotate_redis_secret
            ;;
        jwt)
            rotate_jwt_secret
            ;;
        stellar)
            rotate_stellar_secret
            ;;
        openai)
            rotate_openai_secret
            ;;
        all)
            rotate_database_secret
            rotate_redis_secret
            rotate_jwt_secret
            rotate_stellar_secret
            rotate_openai_secret
            ;;
        *)
            log_error "Unknown secret: ${SECRET_NAME}"
            echo "Valid options: database, redis, jwt, stellar, openai, all"
            exit 1
            ;;
    esac

    restart_deployments
    print_summary
}

# Run main function
main
