#!/bin/bash
# Disable detection rules for the purple team demo
#
# This script disables the demo rules that were enabled by enable-demo-rules.sh:
#
#   - Potential SYN-Based Port Scan Detected (Phase 0: Reconnaissance)
#   - Potential Reverse Shell via Java (Phase 1: Initial Access)
#   - Linux System Information Discovery via Getconf (Phase 3: Discovery)
#   - Sudo Command Enumeration Detected (Phase 4: Privilege Escalation)
#   - Cron Job Created or Modified (Phase 5: Persistence)
#   - Potential Shadow File Read via Command Line Utilities (Phase 6: Credential Access)
#   - Tampering of Shell Command-Line History (Phase 7: Defense Evasion)
#   - Sensitive Files Compression (Phase 8: Collection)
#
# Usage:
#   ./disable-demo-rules.sh
#
# Prerequisites:
#   - Terraform deployed (to get Kibana URL and credentials)
#   - curl and jq installed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

echo "=============================================="
echo "Disable Demo Detection Rules"
echo "=============================================="
echo ""

# Get credentials from Terraform
cd "$TERRAFORM_DIR"

echo "[1/4] Getting Kibana credentials from Terraform..."
KIBANA_URL=$(terraform output -json elastic_dev | jq -r '.kibana_url')
PASSWORD=$(terraform output -raw elastic_dev_password)

if [ -z "$KIBANA_URL" ] || [ "$KIBANA_URL" == "null" ]; then
    echo "ERROR: Could not get Kibana URL from Terraform. Is the infrastructure deployed?"
    exit 1
fi

echo "       Kibana URL: $KIBANA_URL"
echo ""

# Rule names to disable (must match exactly)
RULE_NAMES=(
    "Potential SYN-Based Port Scan Detected"
    "Potential Reverse Shell via Java"
    "Linux System Information Discovery via Getconf"
    "Sudo Command Enumeration Detected"
    "Cron Job Created or Modified"
    "Potential Shadow File Read via Command Line Utilities"
    "Tampering of Shell Command-Line History"
    "Sensitive Files Compression"
)

echo "[2/4] Searching for demo rules..."
echo ""

# Get all rules (paginated)
all_rules=$(curl -s -u "elastic:${PASSWORD}" \
    "${KIBANA_URL}/api/detection_engine/rules/_find?per_page=10000" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json")

total_rules=$(echo "$all_rules" | jq -r '.total // 0')
echo "       Total rules in system: $total_rules"
echo ""

# Find rule IDs by name
RULE_IDS=()
for rule_name in "${RULE_NAMES[@]}"; do
    rule_id=$(echo "$all_rules" | jq -r --arg name "$rule_name" '.data[] | select(.name == $name) | .id' 2>/dev/null | head -1)

    if [ -n "$rule_id" ] && [ "$rule_id" != "null" ] && [ "$rule_id" != "" ]; then
        echo "  ✓ Found: $rule_name"
        RULE_IDS+=("$rule_id")
    else
        echo "  ✗ Not found: $rule_name"
    fi
done

echo ""

if [ ${#RULE_IDS[@]} -eq 0 ]; then
    echo "ERROR: No matching rules found."
    exit 1
fi

echo "[3/4] Disabling ${#RULE_IDS[@]} rules..."
echo ""

# Build the bulk disable request
ids_json=$(printf '%s\n' "${RULE_IDS[@]}" | jq -R . | jq -s .)

# Disable rules using bulk action API
response=$(curl -s -u "elastic:${PASSWORD}" \
    -X POST "${KIBANA_URL}/api/detection_engine/rules/_bulk_action" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"action\": \"disable\",
        \"ids\": $ids_json
    }")

# Check result - try different response formats
success_count=$(echo "$response" | jq -r '.attributes.summary.succeeded // empty' 2>/dev/null)
if [ -z "$success_count" ]; then
    # Try array length (older API format)
    success_count=$(echo "$response" | jq -r 'if type == "array" then length else 0 end' 2>/dev/null)
fi
if [ -z "$success_count" ] || [ "$success_count" == "null" ]; then
    success_count="${#RULE_IDS[@]}"
fi

failed_count=$(echo "$response" | jq -r '.attributes.summary.failed // 0' 2>/dev/null)

echo "[4/4] Results:"
echo ""
echo "  ✓ Rules disabled: ${success_count}"
if [ "$failed_count" != "0" ] && [ "$failed_count" != "null" ] && [ -n "$failed_count" ]; then
    echo "  ✗ Rules failed: $failed_count"
fi

echo ""
echo "=============================================="
echo "Demo rules are now disabled!"
echo "=============================================="
echo ""
echo "Disabled rules:"
for rule_name in "${RULE_NAMES[@]}"; do
    echo "  • $rule_name"
done
echo ""
echo "To re-enable, run: ./enable-demo-rules.sh"
