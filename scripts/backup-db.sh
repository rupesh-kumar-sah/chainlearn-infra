#!/bin/bash
# =============================================================================
# ChainLearn Database Backup Script
# Backs up PostgreSQL database to S3 with encryption
# =============================================================================
# Prerequisites:
#   - AWS CLI configured with appropriate permissions
#   - pg_dump installed
#   - gzip installed
#
# Usage:
#   ./scripts/backup-db.sh [environment]
#   ./scripts/backup-db.sh dev
#   ./scripts/backup-db.sh prod
#
# Cron example (daily at 2 AM):
#   0 2 * * * /path/to/chainlearn-infra/scripts/backup-db.sh prod >> /var/log/chainlearn-backup.log 2>&1
# =============================================================================

set -euo pipefail

# Configuration
ENVIRONMENT="${1:-dev}"
PROJECT_NAME="chainlearn"
AWS_REGION="${AWS_REGION:-us-east-1}"
BACKUP_BUCKET="${PROJECT_NAME}-db-backups-${ENVIRONMENT}"
BACKUP_PREFIX="${ENVIRONMENT}/$(date +%Y/%m/%d)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${PROJECT_NAME}_${ENVIRONMENT}_${TIMESTAMP}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

# Database connection (from AWS Secrets Manager)
DB_HOST=""
DB_PORT="5432"
DB_NAME="chainlearn"
DB_USER="chainlearn_admin"
DB_PASSWORD=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [INFO] $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [SUCCESS] $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [WARN] $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} [ERROR] $1"
}

# -----------------------------------------------------------------------------
# Load Database Credentials
# -----------------------------------------------------------------------------
load_credentials() {
    log_info "Loading database credentials from AWS Secrets Manager..."

    local secret_name="${PROJECT_NAME}-${ENVIRONMENT}-db-master"

    local secret_json
    secret_json=$(aws secretsmanager get-secret-value \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --query 'SecretString' \
        --output text 2>/dev/null)

    if [ -z "${secret_json}" ]; then
        log_error "Failed to retrieve database credentials"
        exit 1
    fi

    DB_HOST=$(echo "${secret_json}" | jq -r '.host')
    DB_PORT=$(echo "${secret_json}" | jq -r '.port // "5432"')
    DB_NAME=$(echo "${secret_json}" | jq -r '.dbname // "chainlearn"')
    DB_USER=$(echo "${secret_json}" | jq -r '.username')
    DB_PASSWORD=$(echo "${secret_json}" | jq -r '.password')

    if [ -z "${DB_HOST}" ] || [ "${DB_HOST}" = "null" ]; then
        log_error "Invalid database credentials"
        exit 1
    fi

    log_success "Database credentials loaded"
}

# -----------------------------------------------------------------------------
# Create S3 Bucket (if not exists)
# -----------------------------------------------------------------------------
ensure_bucket() {
    log_info "Ensuring backup bucket exists..."

    if ! aws s3api head-bucket --bucket "${BACKUP_BUCKET}" 2>/dev/null; then
        log_info "Creating bucket: ${BACKUP_BUCKET}"

        aws s3api create-bucket \
            --bucket "${BACKUP_BUCKET}" \
            --region "${AWS_REGION}" \
            --output text

        # Enable versioning
        aws s3api put-bucket-versioning \
            --bucket "${BACKUP_BUCKET}" \
            --versioning-configuration Status=Enabled

        # Enable encryption
        aws s3api put-bucket-encryption \
            --bucket "${BACKUP_BUCKET}" \
            --server-side-encryption-configuration '{
                "Rules": [
                    {
                        "ApplyServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "aws:kms"
                        }
                    }
                ]
            }'

        # Block public access
        aws s3api put-public-access-block \
            --bucket "${BACKUP_BUCKET}" \
            --public-access-block-configuration \
                "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

        # Set lifecycle policy
        aws s3api put-bucket-lifecycle-configuration \
            --bucket "${BACKUP_BUCKET}" \
            --lifecycle-configuration '{
                "Rules": [
                    {
                        "ID": "DeleteOldBackups",
                        "Status": "Enabled",
                        "Filter": {
                            "Prefix": ""
                        },
                        "Expiration": {
                            "Days": '${RETENTION_DAYS}'
                        },
                        "NoncurrentVersionExpiration": {
                            "NoncurrentDays": 7
                        }
                    }
                ]
            }'

        log_success "Bucket created and configured"
    else
        log_info "Bucket already exists"
    fi
}

# -----------------------------------------------------------------------------
# Perform Backup
# -----------------------------------------------------------------------------
perform_backup() {
    log_info "Starting database backup..."
    log_info "Database: ${DB_NAME} on ${DB_HOST}:${DB_PORT}"

    local backup_dir="/tmp/chainlearn-backup"
    mkdir -p "${backup_dir}"

    local backup_file="${backup_dir}/${BACKUP_NAME}.sql"
    local compressed_file="${backup_dir}/${BACKUP_NAME}.sql.gz"

    # Set password for pg_dump
    export PGPASSWORD="${DB_PASSWORD}"

    # Perform backup with custom format for flexibility
    log_info "Running pg_dump..."
    pg_dump \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --dbname="${DB_NAME}" \
        --format=custom \
        --compress=9 \
        --verbose \
        --file="${backup_file}.dump" \
        2>&1 | tail -5

    # Also create plain SQL backup for easy inspection
    pg_dump \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --dbname="${DB_NAME}" \
        --format=plain \
        --no-owner \
        --no-privileges \
        --file="${backup_file}" \
        2>&1 | tail -5

    # Compress plain SQL backup
    gzip -9 "${backup_file}"

    # Unset password
    unset PGPASSWORD

    log_success "Backup completed"

    # Get file sizes
    local dump_size
    dump_size=$(du -sh "${backup_file}.dump" | cut -f1)
    local gz_size
    gz_size=$(du -sh "${compressed_file}" | cut -f1)

    log_info "Backup sizes: dump=${dump_size}, gzipped=${gz_size}"

    # Upload to S3
    log_info "Uploading to S3..."

    aws s3 cp \
        "${backup_file}.dump" \
        "s3://${BACKUP_BUCKET}/${BACKUP_PREFIX}/${BACKUP_NAME}.dump" \
        --sse aws:kms \
        --storage-class STANDARD_IA \
        --output text

    aws s3 cp \
        "${compressed_file}" \
        "s3://${BACKUP_BUCKET}/${BACKUP_PREFIX}/${BACKUP_NAME}.sql.gz" \
        --sse aws:kms \
        --storage-class STANDARD_IA \
        --output text

    log_success "Backup uploaded to S3"

    # Cleanup local files
    rm -rf "${backup_dir}"
    log_info "Local backup files cleaned up"
}

# -----------------------------------------------------------------------------
# Backup Statistics Schema
# -----------------------------------------------------------------------------
backup_schema() {
    log_info "Backing up schema statistics..."

    local schema_file="/tmp/chainlearn-schema-${TIMESTAMP}.sql"

    export PGPASSWORD="${DB_PASSWORD}"

    pg_dump \
        --host="${DB_HOST}" \
        --port="${DB_PORT}" \
        --username="${DB_USER}" \
        --dbname="${DB_NAME}" \
        --schema-only \
        --file="${schema_file}" \
        2>/dev/null

    unset PGPASSWORD

    aws s3 cp \
        "${schema_file}" \
        "s3://${BACKUP_BUCKET}/${ENVIRONMENT}/schemas/${TIMESTAMP}.sql" \
        --sse aws:kms \
        --output text

    rm -f "${schema_file}"

    log_success "Schema backup completed"
}

# -----------------------------------------------------------------------------
# Verify Backup
# -----------------------------------------------------------------------------
verify_backup() {
    log_info "Verifying backup..."

    local backup_key="${BACKUP_PREFIX}/${BACKUP_NAME}.dump"

    # Check if file exists in S3
    if aws s3api head-object --bucket "${BACKUP_BUCKET}" --key "${backup_key}" &>/dev/null; then
        local size
        size=$(aws s3api head-object \
            --bucket "${BACKUP_BUCKET}" \
            --key "${backup_key}" \
            --query 'ContentLength' \
            --output text)

        log_success "Backup verified: ${backup_key} ($(numfmt --to=iec-i ${size}))"
    else
        log_error "Backup verification failed!"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Send Notification
# -----------------------------------------------------------------------------
send_notification() {
    local status="$1"
    local message="$2"

    local sns_topic_arn
    sns_topic_arn=$(aws sns list-topics \
        --region "${AWS_REGION}" \
        --query "Topics[?contains(TopicArn, '${PROJECT_NAME}-${ENVIRONMENT}-alerts')].TopicArn" \
        --output text 2>/dev/null || echo "")

    if [ -n "${sns_topic_arn}" ]; then
        aws sns publish \
            --topic-arn "${sns_topic_arn}" \
            --subject "ChainLearn DB Backup ${status}: ${ENVIRONMENT}" \
            --message "${message}" \
            --region "${AWS_REGION}" \
            --output text
    fi
}

# -----------------------------------------------------------------------------
# Print Summary
# -----------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "============================================="
    echo "  Database Backup Complete"
    echo "============================================="
    echo ""
    echo "Environment: ${ENVIRONMENT}"
    echo "Backup Name: ${BACKUP_NAME}"
    echo "Location: s3://${BACKUP_BUCKET}/${BACKUP_PREFIX}/"
    echo "Retention: ${RETENTION_DAYS} days"
    echo ""
    echo "Restore command (custom format):"
    echo "  pg_restore -h <host> -U <user> -d ${DB_NAME} ${BACKUP_NAME}.dump"
    echo ""
    echo "Restore command (plain SQL):"
    echo "  gunzip -c ${BACKUP_NAME}.sql.gz | psql -h <host> -U <user> -d ${DB_NAME}"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "============================================="
    echo "  ChainLearn Database Backup"
    echo "============================================="
    echo ""
    echo "Environment: ${ENVIRONMENT}"
    echo "Timestamp: ${TIMESTAMP}"
    echo ""

    load_credentials
    ensure_bucket
    perform_backup
    backup_schema
    verify_backup

    send_notification "SUCCESS" "Database backup completed successfully. Backup: ${BACKUP_NAME}"

    print_summary
}

# Error handling
trap 'send_notification "FAILED" "Database backup failed. Check logs for details."; exit 1' ERR

# Run main function
main
