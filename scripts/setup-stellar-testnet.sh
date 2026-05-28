#!/bin/bash
# =============================================================================
# ChainLearn Stellar Testnet Setup Script
# Creates and funds testnet accounts, deploys Soroban contracts
# =============================================================================
# Prerequisites:
#   - Node.js >= 18
#   - npm install -g stellar-cli
#   - npm install -g soroban-cli
#
# Usage:
#   ./scripts/setup-stellar-testnet.sh [network]
#   ./scripts/setup-stellar-testnet.sh testnet
#   ./scripts/setup-stellar-testnet.sh standalone
# =============================================================================

set -euo pipefail

# Configuration
NETWORK="${1:-testnet}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYS_DIR="${PROJECT_ROOT}/.stellar-keys"
CONTRACTS_DIR="${PROJECT_ROOT}/contracts"

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
# Check Prerequisites
# -----------------------------------------------------------------------------
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js >= 18"
        exit 1
    fi

    if ! command -v stellar &> /dev/null; then
        log_warn "Stellar CLI not found. Installing..."
        cargo install --locked stellar-cli --features opt
    fi

    if ! command -v soroban &> /dev/null; then
        log_warn "Soroban CLI not found. Installing..."
        cargo install --locked soroban-cli
    fi

    log_success "Prerequisites checked"
}

# -----------------------------------------------------------------------------
# Generate Key Pairs
# -----------------------------------------------------------------------------
generate_keys() {
    log_info "Generating Stellar key pairs..."

    mkdir -p "${KEYS_DIR}"

    # Account types to create
    local accounts=("admin" "api" "indexer" "ai" "user1" "user2")

    for account in "${accounts[@]}"; do
        local keyfile="${KEYS_DIR}/${account}.json"

        if [ -f "${keyfile}" ]; then
            log_warn "Key file already exists for ${account}, skipping..."
            continue
        fi

        log_info "Generating key pair for ${account}..."

        # Generate key pair using stellar CLI
        local key_output
        key_output=$(stellar keys generate --network "${NETWORK}" 2>/dev/null || echo "")

        if [ -z "${key_output}" ]; then
            # Fallback: generate using node
            node -e "
                const StellarSdk = require('stellar-sdk');
                const pair = StellarSdk.Keypair.random();
                console.log(JSON.stringify({
                    publicKey: pair.publicKey(),
                    secretKey: pair.secret()
                }));
            " > "${keyfile}" 2>/dev/null || {
                log_error "Failed to generate key pair for ${account}"
                continue
            }
        else
            echo "${key_output}" > "${keyfile}"
        fi

        log_success "Generated key pair for ${account}"
    done
}

# -----------------------------------------------------------------------------
# Fund Accounts via Friendbot
# -----------------------------------------------------------------------------
fund_accounts() {
    log_info "Funding accounts via Friendbot..."

    if [ "${NETWORK}" != "testnet" ]; then
        log_warn "Friendbot is only available on testnet. Skipping funding."
        return
    fi

    local keyfile
    for keyfile in "${KEYS_DIR}"/*.json; do
        if [ ! -f "${keyfile}" ]; then
            continue
        fi

        local account_name
        account_name=$(basename "${keyfile}" .json)
        local public_key
        public_key=$(jq -r '.publicKey' "${keyfile}")

        log_info "Funding ${account_name} (${public_key})..."

        # Fund via Friendbot
        local response
        response=$(curl -s -o /dev/null -w "%{http_code}" \
            "https://friendbot.stellar.org?addr=${public_key}")

        if [ "${response}" = "200" ]; then
            log_success "Funded ${account_name}"
        else
            log_warn "Failed to fund ${account_name} (HTTP ${response}). May already be funded."
        fi

        # Small delay to avoid rate limiting
        sleep 1
    done
}

# -----------------------------------------------------------------------------
# Build Contracts
# -----------------------------------------------------------------------------
build_contracts() {
    log_info "Building Soroban contracts..."

    if [ ! -d "${CONTRACTS_DIR}" ]; then
        log_warn "Contracts directory not found. Skipping build."
        return
    fi

    cd "${CONTRACTS_DIR}"

    # Build all contracts
    if [ -f "Cargo.toml" ]; then
        soroban contract build
        log_success "Contracts built successfully"
    else
        log_warn "No Cargo.toml found in contracts directory"
    fi

    cd "${PROJECT_ROOT}"
}

# -----------------------------------------------------------------------------
# Deploy Contracts
# -----------------------------------------------------------------------------
deploy_contracts() {
    log_info "Deploying Soroban contracts..."

    if [ ! -d "${CONTRACTS_DIR}" ]; then
        log_warn "Contracts directory not found. Skipping deployment."
        return
    fi

    local admin_keyfile="${KEYS_DIR}/admin.json"
    if [ ! -f "${admin_keyfile}" ]; then
        log_error "Admin key file not found. Cannot deploy contracts."
        return
    fi

    local admin_secret
    admin_secret=$(jq -r '.secretKey' "${admin_keyfile}")

    # Contract WASM files to deploy
    local contracts=("chainlearn_core" "chainlearn_rewards")

    for contract in "${contracts[@]}"; do
        local wasm_file="${CONTRACTS_DIR}/target/wasm32-unknown-unknown/release/${contract}.wasm"

        if [ ! -f "${wasm_file}" ]; then
            log_warn "WASM file not found for ${contract}. Skipping."
            continue
        fi

        log_info "Deploying ${contract}..."

        # Upload WASM
        local wasm_hash
        wasm_hash=$(soroban contract upload \
            --network "${NETWORK}" \
            --source "${admin_secret}" \
            --wasm "${wasm_file}" 2>/dev/null)

        if [ -z "${wasm_hash}" ]; then
            log_error "Failed to upload WASM for ${contract}"
            continue
        fi

        log_info "WASM hash: ${wasm_hash}"

        # Deploy contract instance
        local contract_id
        contract_id=$(soroban contract deploy \
            --network "${NETWORK}" \
            --source "${admin_secret}" \
            --wasm-hash "${wasm_hash}" 2>/dev/null)

        if [ -z "${contract_id}" ]; then
            log_error "Failed to deploy ${contract}"
            continue
        fi

        log_success "Deployed ${contract}: ${contract_id}"

        # Save contract ID
        echo "${contract_id}" > "${KEYS_DIR}/${contract}.id"

        # Initialize contract
        initialize_contract "${contract}" "${contract_id}" "${admin_secret}"
    done
}

# -----------------------------------------------------------------------------
# Initialize Contracts
# -----------------------------------------------------------------------------
initialize_contract() {
    local contract_name="$1"
    local contract_id="$2"
    local admin_secret="$3"
    local admin_public
    admin_public=$(jq -r '.publicKey' "${KEYS_DIR}/admin.json")

    log_info "Initializing ${contract_name}..."

    case "${contract_name}" in
        chainlearn_core)
            soroban contract invoke \
                --network "${NETWORK}" \
                --source "${admin_secret}" \
                --id "${contract_id}" \
                -- initialize \
                --admin "${admin_public}" \
                --base_reward "10000000" \
                --max_reward "1000000000" \
                2>/dev/null || log_warn "Failed to initialize ${contract_name}"
            ;;
        chainlearn_rewards)
            soroban contract invoke \
                --network "${NETWORK}" \
                --source "${admin_secret}" \
                --id "${contract_id}" \
                -- initialize \
                --admin "${admin_public}" \
                --token_contract "${CHAINLEARN_CORE_ID:-}" \
                2>/dev/null || log_warn "Failed to initialize ${contract_name}"
            ;;
    esac

    log_success "Initialized ${contract_name}"
}

# -----------------------------------------------------------------------------
# Generate Environment File
# -----------------------------------------------------------------------------
generate_env_file() {
    log_info "Generating environment file..."

    local env_file="${PROJECT_ROOT}/.env.stellar"

    cat > "${env_file}" << EOF
# =============================================================================
# ChainLearn Stellar Configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Network: ${NETWORK}
# =============================================================================

STELLAR_NETWORK=${NETWORK}
STELLAR_HORIZON_URL=$( [ "${NETWORK}" = "mainnet" ] && echo "https://horizon.stellar.org" || echo "https://horizon-testnet.stellar.org" )

# Admin Account
STELLAR_ADMIN_PUBLIC_KEY=$(jq -r '.publicKey' "${KEYS_DIR}/admin.json" 2>/dev/null || echo "")
STELLAR_ADMIN_SECRET_KEY=$(jq -r '.secretKey' "${KEYS_DIR}/admin.json" 2>/dev/null || echo "")

# API Account
STELLAR_API_PUBLIC_KEY=$(jq -r '.publicKey' "${KEYS_DIR}/api.json" 2>/dev/null || echo "")
STELLAR_API_SECRET_KEY=$(jq -r '.secretKey' "${KEYS_DIR}/api.json" 2>/dev/null || echo "")

# Indexer Account
STELLAR_INDEXER_PUBLIC_KEY=$(jq -r '.publicKey' "${KEYS_DIR}/indexer.json" 2>/dev/null || echo "")
STELLAR_INDEXER_SECRET_KEY=$(jq -r '.secretKey' "${KEYS_DIR}/indexer.json" 2>/dev/null || echo "")

# AI Account
STELLAR_AI_PUBLIC_KEY=$(jq -r '.publicKey' "${KEYS_DIR}/ai.json" 2>/dev/null || echo "")
STELLAR_AI_SECRET_KEY=$(jq -r '.secretKey' "${KEYS_DIR}/ai.json" 2>/dev/null || echo "")

# Contract IDs
CHAINLEARN_CORE_CONTRACT_ID=$(cat "${KEYS_DIR}/chainlearn_core.id" 2>/dev/null || echo "")
CHAINLEARN_REWARDS_CONTRACT_ID=$(cat "${KEYS_DIR}/chainlearn_rewards.id" 2>/dev/null || echo "")
EOF

    log_success "Environment file generated: ${env_file}"
}

# -----------------------------------------------------------------------------
# Print Summary
# -----------------------------------------------------------------------------
print_summary() {
    echo ""
    echo "============================================="
    echo "  ChainLearn Stellar Testnet Setup Complete"
    echo "============================================="
    echo ""
    echo "Network: ${NETWORK}"
    echo "Keys Directory: ${KEYS_DIR}"
    echo ""

    echo "Accounts:"
    for keyfile in "${KEYS_DIR}"/*.json; do
        if [ -f "${keyfile}" ]; then
            local name
            name=$(basename "${keyfile}" .json)
            local pubkey
            pubkey=$(jq -r '.publicKey' "${keyfile}")
            echo "  ${name}: ${pubkey}"
        fi
    done

    echo ""
    echo "Contract IDs:"
    for idfile in "${KEYS_DIR}"/*.id; do
        if [ -f "${idfile}" ]; then
            local name
            name=$(basename "${idfile}" .id)
            local contract_id
            contract_id=$(cat "${idfile}")
            echo "  ${name}: ${contract_id}"
        fi
    done

    echo ""
    echo "Environment file: ${PROJECT_ROOT}/.env.stellar"
    echo ""
    echo "Next steps:"
    echo "  1. Copy .env.stellar to your service directories"
    echo "  2. Update your service configurations"
    echo "  3. Run 'docker compose -f docker/docker-compose.dev.yml up'"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "============================================="
    echo "  ChainLearn Stellar Testnet Setup"
    echo "============================================="
    echo ""

    check_prerequisites
    generate_keys
    fund_accounts
    build_contracts
    deploy_contracts
    generate_env_file
    print_summary
}

# Run main function
main
