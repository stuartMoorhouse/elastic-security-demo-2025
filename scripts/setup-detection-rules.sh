#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Detection Rules CLI Setup${NC}"
echo -e "${BLUE}Elastic Local Environment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Determine script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

# Check if terraform directory exists
if [ ! -d "$TERRAFORM_DIR" ]; then
    echo -e "${RED}Error: terraform directory not found at $TERRAFORM_DIR${NC}"
    exit 1
fi

cd "$TERRAFORM_DIR"

# Check if terraform state exists
if [ ! -f "../state/terraform.tfstate" ]; then
    echo -e "${RED}Error: Terraform state not found${NC}"
    echo "Please run 'terraform apply' first"
    exit 1
fi

echo -e "${YELLOW}Step 1: Extracting Terraform outputs...${NC}"

# Extract outputs from terraform
export LOCAL_CLOUD_ID=$(terraform output -json elastic_local | jq -r '.cloud_id')
export LOCAL_KIBANA_URL=$(terraform output -json elastic_local | jq -r '.kibana_url')
export LOCAL_ELASTICSEARCH_URL=$(terraform output -json elastic_local | jq -r '.elasticsearch_url')
export LOCAL_ELASTICSEARCH_USER=$(terraform output -json elastic_local | jq -r '.elasticsearch_user')
export LOCAL_ELASTICSEARCH_PASSWORD=$(terraform output -raw elastic_local_password)

echo -e "${GREEN}✓ Cloud ID: ${LOCAL_CLOUD_ID:0:30}...${NC}"
echo -e "${GREEN}✓ Kibana URL: ${LOCAL_KIBANA_URL}${NC}"
echo -e "${GREEN}✓ Elasticsearch URL: ${LOCAL_ELASTICSEARCH_URL}${NC}"
echo -e "${GREEN}✓ Username: ${LOCAL_ELASTICSEARCH_USER}${NC}"
echo ""

echo -e "${YELLOW}Step 2: Creating API Key in Elasticsearch...${NC}"

# Create API key using Elasticsearch API with Kibana privileges
API_KEY_RESPONSE=$(curl -s -X POST "${LOCAL_ELASTICSEARCH_URL}/_security/api_key" \
  -H "Content-Type: application/json" \
  -u "${LOCAL_ELASTICSEARCH_USER}:${LOCAL_ELASTICSEARCH_PASSWORD}" \
  -d '{
    "name": "detection-rules-local",
    "expiration": "30d",
    "role_descriptors": {
      "detection_rules": {
        "cluster": ["all"],
        "indices": [
          {
            "names": ["*"],
            "privileges": ["all"]
          }
        ],
        "applications": [
          {
            "application": "kibana-.kibana",
            "privileges": ["all"],
            "resources": ["*"]
          }
        ]
      }
    },
    "metadata": {
      "application": "detection-rules",
      "environment": "local"
    }
  }')

# Check if API key creation was successful
if echo "$API_KEY_RESPONSE" | jq -e '.encoded' > /dev/null 2>&1; then
    export LOCAL_API_KEY=$(echo "$API_KEY_RESPONSE" | jq -r '.encoded')
    API_KEY_NAME=$(echo "$API_KEY_RESPONSE" | jq -r '.name')
    echo -e "${GREEN}✓ API Key created: ${API_KEY_NAME}${NC}"
    echo -e "${GREEN}✓ API Key: ${LOCAL_API_KEY:0:20}...${NC}"
else
    echo -e "${RED}Error creating API key:${NC}"
    echo "$API_KEY_RESPONSE" | jq '.'
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 3: Exporting environment variables...${NC}"

# Create environment file
ENV_FILE="$SCRIPT_DIR/.env-detection-rules"
cat > "$ENV_FILE" << EOF
# Detection Rules CLI Environment Variables
# Generated: $(date)
# Source this file: source scripts/.env-detection-rules

export LOCAL_CLOUD_ID="${LOCAL_CLOUD_ID}"
export LOCAL_KIBANA_URL="${LOCAL_KIBANA_URL}"
export LOCAL_ELASTICSEARCH_USER="${LOCAL_ELASTICSEARCH_USER}"
export LOCAL_ELASTICSEARCH_PASSWORD="${LOCAL_ELASTICSEARCH_PASSWORD}"
export LOCAL_API_KEY="${LOCAL_API_KEY}"
EOF

echo -e "${GREEN}✓ Environment variables saved to: scripts/.env-detection-rules${NC}"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Setup Complete!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo -e "${YELLOW}To use these variables in your current shell:${NC}"
echo -e "  ${GREEN}source scripts/.env-detection-rules${NC}"
echo ""

echo -e "${YELLOW}Example: Export rule from Local Kibana${NC}"
echo -e "  ${GREEN}python -m detection_rules kibana \\${NC}"
echo -e "  ${GREEN}  --cloud-id=\"\${LOCAL_CLOUD_ID}\" \\${NC}"
echo -e "  ${GREEN}  --api-key=\"\${LOCAL_API_KEY}\" \\${NC}"
echo -e "  ${GREEN}  export-rules \\${NC}"
echo -e "  ${GREEN}  --rule-id \"YOUR_RULE_ID\" \\${NC}"
echo -e "  ${GREEN}  -o custom-rules/rules/${NC}"
echo ""

echo -e "${YELLOW}Example: Import rules to Local Kibana${NC}"
echo -e "  ${GREEN}python -m detection_rules kibana \\${NC}"
echo -e "  ${GREEN}  --cloud-id=\"\${LOCAL_CLOUD_ID}\" \\${NC}"
echo -e "  ${GREEN}  --api-key=\"\${LOCAL_API_KEY}\" \\${NC}"
echo -e "  ${GREEN}  import-rules \\${NC}"
echo -e "  ${GREEN}  -d custom-rules/rules/${NC}"
echo ""

echo -e "${YELLOW}Quick Access:${NC}"
echo -e "  Kibana URL: ${GREEN}${LOCAL_KIBANA_URL}${NC}"
echo -e "  Username: ${GREEN}${LOCAL_ELASTICSEARCH_USER}${NC}"
echo -e "  Password: ${GREEN}${LOCAL_ELASTICSEARCH_PASSWORD}${NC}"
echo ""

echo -e "${YELLOW}Note:${NC} The API key will expire in 30 days. Re-run this script to generate a new one."
echo ""
