#!/bin/bash

################################################################################
# Elastic Security Demo - Elastic Agent Deployment Script
#
# Purpose: Automates deployment of Elastic Agent with Defend integration
#          on blue-01 VM for security detection demonstration
#
# Prerequisites:
#   - Elastic Cloud dev deployment (elastic-security-demo-dev) is running
#   - Blue-01 VM is provisioned and setup-blue-vm.sh has completed
#   - Terraform outputs are available
#
# Usage:
#   export KIBANA_URL=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.kibana_url')
#   export ELASTIC_PASSWORD=$(cd terraform && terraform output -raw elastic_dev_password)
#   export DEPLOYMENT_NAME=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.deployment_name')
#   export DEPLOYMENT_ID=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.deployment_id')
#   export ELASTICSEARCH_URL=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.elasticsearch_url')
#   export BLUE_VM_IP=$(cd terraform && terraform output -json blue_vm | jq -r '.value.public_ip')
#   export ELASTIC_VERSION=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.version')
#   ./scripts/deploy-elastic-agent.sh
#
# Environment Variables Required:
#   KIBANA_URL         - Kibana URL from terraform output
#   ELASTIC_USER       - Elasticsearch username (default: elastic)
#   ELASTIC_PASSWORD   - Elasticsearch password from terraform output
#   FLEET_URL          - Fleet Server URL (from Kibana integrations)
#   BLUE_VM_IP         - Public IP of blue-01 VM
#   SSH_KEY            - Path to SSH private key (default: ~/.ssh/id_ed25519)
#   ELASTIC_VERSION    - Elastic Stack version from Terraform
#
# Author: Stuart, Elastic Security Sales Engineering
# Last Updated: November 2025
################################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to construct Fleet Server URL from deployment info
construct_fleet_url() {
    local deployment_name="$1"
    local deployment_id="$2"
    local es_url="$3"

    # Extract first 6 characters of deployment ID
    local id_prefix="${deployment_id:0:6}"

    # Extract region from Elasticsearch URL
    # Format: https://xxx.{region}.aws.found.io:443
    local region=$(echo "$es_url" | sed -n 's/.*\.\([^.]*\)\.aws\.found\.io.*/\1/p')

    # Construct Fleet Server URL
    echo "https://${deployment_name}-${id_prefix}.fleet.${region}.aws.found.io"
}

################################################################################
# CONFIGURATION
################################################################################

# Default values
ELASTIC_USER="${ELASTIC_USER:-elastic}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_USER="ubuntu"
POLICY_NAME="Blue Team - Endpoint Security"

# Check required environment variables
check_env_vars() {
    local missing_vars=()

    if [ -z "$KIBANA_URL" ]; then
        missing_vars+=("KIBANA_URL")
    fi

    if [ -z "$ELASTIC_PASSWORD" ]; then
        missing_vars+=("ELASTIC_PASSWORD")
    fi

    if [ -z "$DEPLOYMENT_NAME" ]; then
        missing_vars+=("DEPLOYMENT_NAME")
    fi

    if [ -z "$DEPLOYMENT_ID" ]; then
        missing_vars+=("DEPLOYMENT_ID")
    fi

    if [ -z "$ELASTICSEARCH_URL" ]; then
        missing_vars+=("ELASTICSEARCH_URL")
    fi

    if [ -z "$BLUE_VM_IP" ]; then
        missing_vars+=("BLUE_VM_IP")
    fi

    if [ -z "$ELASTIC_VERSION" ]; then
        missing_vars+=("ELASTIC_VERSION")
    fi

    if [ ${#missing_vars[@]} -gt 0 ]; then
        print_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        echo ""
        echo "Example usage:"
        echo "  export KIBANA_URL=\$(cd terraform && terraform output -json elastic_dev | jq -r '.value.kibana_url')"
        echo "  export ELASTIC_PASSWORD=\$(cd terraform && terraform output -raw elastic_dev_password)"
        echo "  export DEPLOYMENT_NAME=\$(cd terraform && terraform output -json elastic_dev | jq -r '.value.deployment_name')"
        echo "  export DEPLOYMENT_ID=\$(cd terraform && terraform output -json elastic_dev | jq -r '.value.deployment_id')"
        echo "  export ELASTICSEARCH_URL=\$(cd terraform && terraform output -json elastic_dev | jq -r '.value.elasticsearch_url')"
        echo "  export BLUE_VM_IP=\$(cd terraform && terraform output -json blue_vm | jq -r '.value.public_ip')"
        echo "  export ELASTIC_VERSION=\$(cd terraform && terraform output -json elastic_dev | jq -r '.value.version')"
        echo "  ./scripts/deploy-elastic-agent.sh"
        exit 1
    fi
}

################################################################################
# MAIN SCRIPT
################################################################################

echo "=========================================="
echo "Elastic Agent Deployment - Blue Team VM"
echo "=========================================="
echo ""

check_env_vars

# Construct Fleet Server URL from deployment info
FLEET_URL=$(construct_fleet_url "$DEPLOYMENT_NAME" "$DEPLOYMENT_ID" "$ELASTICSEARCH_URL")
print_info "Constructed Fleet Server URL: $FLEET_URL"

print_info "Configuration:"
echo "  Kibana URL: $KIBANA_URL"
echo "  Fleet URL: $FLEET_URL"
echo "  Elasticsearch URL: $ELASTICSEARCH_URL"
echo "  Blue VM IP: $BLUE_VM_IP"
echo "  SSH Key: $SSH_KEY"
echo "  Policy Name: $POLICY_NAME"
echo "  Elastic Version: $ELASTIC_VERSION"
echo ""

# Wait for SSH access with retry logic (VM may still be booting)
print_step "Waiting for SSH access to blue-01 (VM may still be booting)..."
MAX_SSH_ATTEMPTS=30
SSH_WAIT_INTERVAL=10
SSH_CONNECTED=false

for attempt in $(seq 1 $MAX_SSH_ATTEMPTS); do
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null "$SSH_USER@$BLUE_VM_IP" "echo 'SSH connection successful'" > /dev/null 2>&1; then
        SSH_CONNECTED=true
        break
    fi
    print_info "SSH attempt $attempt/$MAX_SSH_ATTEMPTS failed, waiting ${SSH_WAIT_INTERVAL}s..."
    sleep $SSH_WAIT_INTERVAL
done

if [ "$SSH_CONNECTED" = false ]; then
    print_error "Cannot connect to blue-01 via SSH after $MAX_SSH_ATTEMPTS attempts"
    print_error "Verify the VM is running and SSH_KEY is correct"
    exit 1
fi
print_info "✓ SSH access verified"
echo ""

################################################################################
# STEP 1: Create Agent Policy with Defend Integration via Fleet API
################################################################################

print_step "[1/4] Creating or using existing agent policy with Defend integration..."

# Check if policy already exists
print_info "Checking for existing policy..."
EXISTING_POLICIES=$(curl -s --request GET \
  --url "${KIBANA_URL}/api/fleet/agent_policies" \
  --user "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
  --header "kbn-xsrf: true")

POLICY_ID=$(echo "$EXISTING_POLICIES" | jq -r ".items[] | select(.name==\"${POLICY_NAME}\") | .id")

if [ -n "$POLICY_ID" ] && [ "$POLICY_ID" != "null" ]; then
    print_info "✓ Using existing agent policy: $POLICY_ID"
else
    # Create the agent policy with system monitoring
    print_info "Creating new agent policy..."
    POLICY_RESPONSE=$(curl -s --request POST \
      --url "${KIBANA_URL}/api/fleet/agent_policies?sys_monitoring=true" \
      --user "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
      --header "Content-Type: application/json" \
      --header "kbn-xsrf: true" \
      --data '{
        "name": "'"${POLICY_NAME}"'",
        "namespace": "default",
        "description": "Policy for blue-01 VM with Elastic Defend integration for security monitoring",
        "monitoring_enabled": ["logs", "metrics"]
      }')

    # Extract policy ID
    POLICY_ID=$(echo "$POLICY_RESPONSE" | jq -r '.item.id')

    if [ -z "$POLICY_ID" ] || [ "$POLICY_ID" = "null" ]; then
        print_error "Failed to create agent policy"
        echo "Response: $POLICY_RESPONSE"
        exit 1
    fi

    print_info "✓ Agent policy created: $POLICY_ID"
fi

################################################################################
# STEP 1b: Add Elastic Defend Integration (3-step process per CLAUDE.md)
################################################################################

print_info "Adding Elastic Defend integration to policy..."

# Extract major.minor version for package version
PACKAGE_VERSION=$(echo "$ELASTIC_VERSION" | cut -d. -f1,2).0

# Step 2a: Create Defend integration with default settings (EDRComplete preset)
print_info "  [2a/3] Creating Elastic Defend integration with default settings..."

DEFEND_RESPONSE=$(curl -s --request POST \
  --url "${KIBANA_URL}/api/fleet/package_policies" \
  --user "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
  --header "Content-Type: application/json" \
  --header "kbn-xsrf: true" \
  --header "kbn-version: ${ELASTIC_VERSION}" \
  --data '{
    "name": "Elastic Defend - Detect Mode",
    "description": "Defend integration in detect mode",
    "namespace": "default",
    "policy_id": "'"${POLICY_ID}"'",
    "enabled": true,
    "inputs": [
      {
        "enabled": true,
        "streams": [],
        "type": "ENDPOINT_INTEGRATION_CONFIG",
        "config": {
          "_config": {
            "value": {
              "type": "endpoint",
              "endpointConfig": {
                "preset": "EDRComplete"
              }
            }
          }
        }
      }
    ],
    "package": {
      "name": "endpoint",
      "title": "Elastic Defend",
      "version": "'"${PACKAGE_VERSION}"'"
    }
  }')

PACKAGE_POLICY_ID=$(echo "$DEFEND_RESPONSE" | jq -r '.item.id')

if [ -z "$PACKAGE_POLICY_ID" ] || [ "$PACKAGE_POLICY_ID" = "null" ]; then
    print_error "Failed to create Defend integration"
    echo "Response: $DEFEND_RESPONSE"
    exit 1
fi

print_info "  ✓ Defend integration created: $PACKAGE_POLICY_ID"

# Step 2b: GET the current package policy configuration
print_info "  [2b/3] Retrieving current Defend configuration..."

CURRENT_CONFIG=$(curl -s --request GET \
  --url "${KIBANA_URL}/api/fleet/package_policies/${PACKAGE_POLICY_ID}" \
  --user "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
  --header "kbn-xsrf: true" \
  --header "kbn-version: ${ELASTIC_VERSION}")

if [ -z "$CURRENT_CONFIG" ] || [ "$CURRENT_CONFIG" = "null" ]; then
    print_error "Failed to retrieve current configuration"
    exit 1
fi

print_info "  ✓ Current configuration retrieved"

# Step 2c: PUT to update to detect mode
print_info "  [2c/3] Updating Defend integration to detect mode..."

UPDATE_RESPONSE=$(curl -s --request PUT \
  --url "${KIBANA_URL}/api/fleet/package_policies/${PACKAGE_POLICY_ID}" \
  --user "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
  --header "Content-Type: application/json" \
  --header "kbn-xsrf: true" \
  --header "kbn-version: ${ELASTIC_VERSION}" \
  --data '{
    "name": "Elastic Defend - Detect Mode",
    "namespace": "default",
    "policy_id": "'"${POLICY_ID}"'",
    "enabled": true,
    "package": {
      "name": "endpoint",
      "title": "Elastic Defend",
      "version": "'"${PACKAGE_VERSION}"'"
    },
    "inputs": [
      {
        "type": "endpoint",
        "enabled": true,
        "streams": [],
        "config": {
          "policy": {
            "value": {
              "windows": {
                "malware": { "mode": "detect" },
                "ransomware": { "mode": "detect" },
                "memory_protection": { "mode": "detect" },
                "behavior_protection": { "mode": "detect" }
              },
              "mac": {
                "malware": { "mode": "detect" },
                "behavior_protection": { "mode": "detect" },
                "memory_protection": { "mode": "detect" }
              },
              "linux": {
                "malware": { "mode": "detect" },
                "behavior_protection": { "mode": "detect" },
                "memory_protection": { "mode": "detect" }
              }
            }
          }
        }
      }
    ]
  }')

UPDATE_SUCCESS=$(echo "$UPDATE_RESPONSE" | jq -r '.success')

if [ "$UPDATE_SUCCESS" != "true" ]; then
    print_warn "Detect mode update may have failed, but continuing..."
    echo "Response: $UPDATE_RESPONSE"
else
    print_info "  ✓ Defend integration configured to detect mode"
fi

print_info "✓ Elastic Defend integration fully configured"
echo ""

################################################################################
# STEP 2: Get Enrollment Token
################################################################################

print_step "[2/4] Retrieving enrollment token..."

# Wait a moment for policy to be fully created
sleep 2

ENROLLMENT_RESPONSE=$(curl -s --request GET \
  --url "${KIBANA_URL}/api/fleet/enrollment_api_keys" \
  --user "${ELASTIC_USER}:${ELASTIC_PASSWORD}" \
  --header "kbn-xsrf: true")

ENROLLMENT_TOKEN=$(echo "$ENROLLMENT_RESPONSE" | jq -r ".items[] | select(.policy_id==\"${POLICY_ID}\") | .api_key")

if [ -z "$ENROLLMENT_TOKEN" ] || [ "$ENROLLMENT_TOKEN" = "null" ]; then
    print_error "Failed to retrieve enrollment token"
    echo "Response: $ENROLLMENT_RESPONSE"
    exit 1
fi

print_info "✓ Enrollment token retrieved"
echo ""

################################################################################
# STEP 3: Download and Extract Agent on Blue-01
################################################################################

print_step "[3/4] Installing Elastic Agent on blue-01..."

print_info "Downloading Elastic Agent ${ELASTIC_VERSION}..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null "$SSH_USER@$BLUE_VM_IP" bash << EOSSH
set -e

cd /tmp

# Download agent
echo "Downloading Elastic Agent ${ELASTIC_VERSION}..."
curl -L -O "https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-${ELASTIC_VERSION}-linux-x86_64.tar.gz" 2>&1

# Extract agent
echo "Extracting Elastic Agent..."
tar xzf "elastic-agent-${ELASTIC_VERSION}-linux-x86_64.tar.gz"

echo "Agent downloaded and extracted successfully"
EOSSH

print_info "✓ Agent downloaded and extracted on blue-01"
echo ""

################################################################################
# STEP 4: Install and Enroll Agent
################################################################################

print_step "[4/4] Enrolling and installing Elastic Agent..."

print_info "This will install the agent as a system service..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null "$SSH_USER@$BLUE_VM_IP" bash << EOSSH
set -e

cd /tmp/elastic-agent-${ELASTIC_VERSION}-linux-x86_64

# Install agent with enrollment (requires sudo)
echo "Installing Elastic Agent with Fleet enrollment..."
sudo ./elastic-agent install \\
  --url="${FLEET_URL}" \\
  --enrollment-token="${ENROLLMENT_TOKEN}" \\
  --force \\
  --non-interactive

echo "Agent installation completed"
EOSSH

print_info "✓ Elastic Agent installed and enrolled"
echo ""

################################################################################
# VERIFICATION
################################################################################

print_step "Verifying agent status..."

sleep 5

# Check agent status on remote host
AGENT_STATUS=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null "$SSH_USER@$BLUE_VM_IP" \
  "sudo elastic-agent status" 2>&1 || echo "error")

if echo "$AGENT_STATUS" | grep -q "healthy"; then
    print_info "✓ Agent is healthy and connected"
elif echo "$AGENT_STATUS" | grep -q "online"; then
    print_info "✓ Agent is online"
else
    print_warn "Agent status unclear - check Fleet UI for confirmation"
fi

echo ""

################################################################################
# COMPLETION
################################################################################

echo "=========================================="
echo "Elastic Agent Deployment Complete!"
echo "=========================================="
echo ""

print_info "Summary:"
echo "  Policy ID: $POLICY_ID"
echo "  Policy Name: $POLICY_NAME"
echo "  Integration: Elastic Defend (EDR Complete preset, detect mode)"
echo "  Elastic Version: $ELASTIC_VERSION"
echo "  Managed by: elastic-security-demo-dev"
echo ""

print_info "Verify enrollment in Kibana Fleet UI:"
echo "  ${KIBANA_URL}/app/fleet/agents"
echo ""

print_info "Check agent status on blue-01:"
echo "  ssh -i $SSH_KEY $SSH_USER@$BLUE_VM_IP 'sudo elastic-agent status'"
echo ""

print_info "View agent logs on blue-01:"
echo "  ssh -i $SSH_KEY $SSH_USER@$BLUE_VM_IP 'sudo journalctl -u elastic-agent -f'"
echo ""

################################################################################
# SAVE CONFIGURATION
################################################################################

CONFIG_FILE="./elastic-agent-deployment-info.txt"

cat > "$CONFIG_FILE" << ENDCONFIG
Elastic Agent Deployment - Blue Team VM
Generated: $(date)

Deployment Information:
  Policy ID: $POLICY_ID
  Policy Name: $POLICY_NAME
  Integration: Elastic Defend (EDR Complete)
  Elastic Version: $ELASTIC_VERSION
  Deployment: elastic-security-demo-dev

Target VM:
  IP Address: $BLUE_VM_IP
  SSH User: $SSH_USER

Fleet Configuration:
  Kibana URL: $KIBANA_URL
  Fleet URL: $FLEET_URL

Verification Commands:
  Check Fleet UI: ${KIBANA_URL}/app/fleet/agents
  Agent Status: ssh -i $SSH_KEY $SSH_USER@$BLUE_VM_IP 'sudo elastic-agent status'
  Agent Logs: ssh -i $SSH_KEY $SSH_USER@$BLUE_VM_IP 'sudo journalctl -u elastic-agent -f'

Next Steps:
  1. Verify agent appears in Fleet UI (${KIBANA_URL}/app/fleet)
  2. Confirm Elastic Defend integration is active
  3. Proceed with red team attack simulation
  4. Monitor detections in Security app (${KIBANA_URL}/app/security)

ENDCONFIG

print_info "Configuration saved to: $CONFIG_FILE"

echo ""
print_info "Blue-01 is now protected and ready for the purple team exercise!"
echo ""

################################################################################
# END OF SCRIPT
################################################################################
