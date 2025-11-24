#!/bin/bash

################################################################################
# Ingest Test Data into Local Elasticsearch
#
# This script ingests true-positive.json and true-negative.json test data
# into the Local Elasticsearch instance (ec-local) for testing the
# Tomcat webshell detection rule.
#
# Usage: ./ingest-test-data.sh
################################################################################

set -e

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo "=========================================="
echo "Ingest Test Data to Local Elasticsearch"
echo "=========================================="
echo ""

# Check if we're in the correct directory
if [ ! -f "data/test-data/true-positive.json" ] || [ ! -f "data/test-data/true-negative.json" ]; then
    print_error "Test data files not found. Please run this script from the project root directory."
    exit 1
fi

# Get Elasticsearch endpoint and password from terraform
print_info "Getting Elasticsearch credentials from Terraform..."

# Determine if we need to cd to terraform directory
if [ -d "terraform" ]; then
    cd terraform
elif [ -f "state/terraform.tfstate" ]; then
    # Already in terraform directory or subdirectory
    :
else
    print_error "Terraform state not found. Have you run 'terraform apply'?"
    exit 1
fi

# Check for state file
if [ ! -f "state/terraform.tfstate" ] && [ ! -f "terraform.tfstate" ]; then
    print_error "Terraform state not found. Have you run 'terraform apply'?"
    exit 1
fi

ES_ENDPOINT=$(terraform output -json elastic_local 2>/dev/null | jq -r '.elasticsearch_url')
ES_PASSWORD=$(terraform output -raw elastic_local_password 2>/dev/null)

if [ -z "$ES_ENDPOINT" ] || [ -z "$ES_PASSWORD" ]; then
    print_error "Could not retrieve Elasticsearch credentials from Terraform."
    print_error "Please ensure 'terraform apply' has completed successfully."
    exit 1
fi

# Return to project root
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo ..)"

print_info "Elasticsearch endpoint: $ES_ENDPOINT"
print_info "Using elastic user credentials"
echo ""

# Target index
INDEX_NAME="logs-endpoint.events.default"

# Function to ingest a document
ingest_document() {
    local file=$1
    local description=$2

    print_info "Ingesting $description..."

    response=$(curl -s -w "\n%{http_code}" -u "elastic:${ES_PASSWORD}" \
        -X POST "${ES_ENDPOINT}/${INDEX_NAME}/_doc" \
        -H 'Content-Type: application/json' \
        -d @"${file}")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n -1)

    if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
        doc_id=$(echo "$body" | jq -r '._id')
        print_info "✓ Success! Document ID: $doc_id"
        return 0
    else
        print_error "✗ Failed with HTTP $http_code"
        echo "$body" | jq '.' 2>/dev/null || echo "$body"
        return 1
    fi
}

# Create index with proper mappings (if it doesn't exist)
print_info "Checking if index exists..."
index_exists=$(curl -s -u "elastic:${ES_PASSWORD}" \
    -o /dev/null -w "%{http_code}" \
    "${ES_ENDPOINT}/${INDEX_NAME}")

if [ "$index_exists" -eq 404 ]; then
    print_warn "Index does not exist, creating it..."

    curl -s -u "elastic:${ES_PASSWORD}" \
        -X PUT "${ES_ENDPOINT}/${INDEX_NAME}" \
        -H 'Content-Type: application/json' \
        -d '{
          "settings": {
            "number_of_shards": 1,
            "number_of_replicas": 0
          }
        }' | jq '.' || true

    print_info "✓ Index created"
else
    print_info "✓ Index already exists"
fi

echo ""

# Ingest test documents
print_info "Ingesting test data..."
echo ""

success_count=0
fail_count=0

if ingest_document "data/test-data/true-positive.json" "True Positive (Tomcat spawning bash -c)"; then
    ((success_count++))
else
    ((fail_count++))
fi

echo ""

if ingest_document "data/test-data/true-negative.json" "True Negative (Elasticsearch spawning ls)"; then
    ((success_count++))
else
    ((fail_count++))
fi

echo ""
echo "=========================================="
echo "Ingestion Summary"
echo "=========================================="
echo "Successfully ingested: $success_count documents"
echo "Failed: $fail_count documents"
echo ""

if [ $fail_count -eq 0 ]; then
    print_info "✓ All test data ingested successfully!"
    echo ""
    print_info "Next steps:"
    echo "  1. Open Local Kibana: $(cd terraform && terraform output -json elastic_local | jq -r '.kibana_url')"
    echo "  2. Navigate to: Security → Rules → Detection rules (SIEM)"
    echo "  3. Create the Tomcat webshell detection rule"
    echo "  4. Run the rule to test against ingested data"
    echo ""
    print_info "To verify ingestion:"
    echo "  curl -u elastic:PASSWORD '${ES_ENDPOINT}/${INDEX_NAME}/_search?pretty' | jq '.hits.total'"
    exit 0
else
    print_error "Some documents failed to ingest. Please check the errors above."
    exit 1
fi
