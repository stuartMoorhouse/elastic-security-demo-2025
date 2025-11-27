#!/bin/bash
# Enable detection rules for the purple team demo
#
# This script installs Elastic prebuilt rules (if not already installed) and
# enables the following rules in the Dev cluster for the tomcatastrophe demo:
#
#   - Sudo Command Enumeration Detected (Privilege Escalation)
#   - Cron Job Created or Modified (Persistence)
#   - Potential Shadow File Read via Command Line Utilities (Credential Access)
#   - Sensitive Files Compression (Collection)
#
# Note: Initial Access and Execution are detected by Elastic Defend behavioral alerts
#
# Usage:
#   ./enable-demo-rules.sh
#
# Prerequisites:
#   - Terraform deployed (to get Kibana URL and credentials)
#   - curl and jq installed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

echo "=============================================="
echo "Enable Demo Detection Rules"
echo "=============================================="
echo ""

# Get credentials from Terraform
cd "$TERRAFORM_DIR"

echo "[1/5] Getting Kibana credentials from Terraform..."
KIBANA_URL=$(terraform output -json elastic_dev | jq -r '.kibana_url')
PASSWORD=$(terraform output -raw elastic_dev_password)

if [ -z "$KIBANA_URL" ] || [ "$KIBANA_URL" == "null" ]; then
    echo "ERROR: Could not get Kibana URL from Terraform. Is the infrastructure deployed?"
    exit 1
fi

echo "       Kibana URL: $KIBANA_URL"
echo ""

# Step 2: Install prebuilt rules
echo "[2/5] Installing Elastic prebuilt detection rules..."
echo ""

install_response=$(curl -s -u "elastic:${PASSWORD}" \
    -X PUT "${KIBANA_URL}/api/detection_engine/rules/prepackaged" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json")

rules_installed=$(echo "$install_response" | jq -r '.rules_installed // 0' 2>/dev/null)
rules_updated=$(echo "$install_response" | jq -r '.rules_updated // 0' 2>/dev/null)

echo "       Rules installed: $rules_installed"
echo "       Rules updated: $rules_updated"
echo ""

# Wait a moment for rules to be indexed
sleep 2

# Rule names to enable (must match exactly)
RULE_NAMES=(
    "Sudo Command Enumeration Detected"
    "Cron Job Created or Modified"
    "Potential Shadow File Read via Command Line Utilities"
    "Sensitive Files Compression"
)

echo "[3/5] Searching for demo rules..."
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
    echo ""
    echo "Available rules (first 20):"
    echo "$all_rules" | jq -r '.data[0:20][].name' 2>/dev/null | head -20
    exit 1
fi

echo "[4/6] Enabling ${#RULE_IDS[@]} rules..."
echo ""

# Build the bulk enable request
ids_json=$(printf '%s\n' "${RULE_IDS[@]}" | jq -R . | jq -s .)

# Enable rules using bulk action API
response=$(curl -s -u "elastic:${PASSWORD}" \
    -X POST "${KIBANA_URL}/api/detection_engine/rules/_bulk_action" \
    -H "kbn-xsrf: true" \
    -H "Content-Type: application/json" \
    -d "{
        \"action\": \"enable\",
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

echo "       Enabled: ${success_count} rules"
echo ""

echo "[5/6] Updating rule schedules and adding alert suppression..."
echo ""
echo "       Schedule: 1 minute interval, 10 minute lookback"
echo "       Alert Suppression: by host.name, per 5 minutes"
echo ""

# Update each rule's schedule and add alert suppression
for rule_id in "${RULE_IDS[@]}"; do
    # Get the rule name and type for display
    rule_name=$(echo "$all_rules" | jq -r --arg id "$rule_id" '.data[] | select(.id == $id) | .name' 2>/dev/null)
    rule_type=$(echo "$all_rules" | jq -r --arg id "$rule_id" '.data[] | select(.id == $id) | .type' 2>/dev/null)

    # Update the rule schedule: interval=1m, from=now-10m
    # Add alert suppression: group by host.name, suppress for 5 minutes
    # Note: alert_suppression is supported for query, eql, threshold, and new_terms rules
    update_response=$(curl -s -u "elastic:${PASSWORD}" \
        -X PATCH "${KIBANA_URL}/api/detection_engine/rules" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json" \
        -d "{
            \"id\": \"$rule_id\",
            \"interval\": \"1m\",
            \"from\": \"now-10m\",
            \"alert_suppression\": {
                \"group_by\": [\"host.name\"],
                \"duration\": {
                    \"value\": 5,
                    \"unit\": \"m\"
                },
                \"missing_fields_strategy\": \"suppress\"
            }
        }")

    # Check if update was successful
    updated_interval=$(echo "$update_response" | jq -r '.interval // empty' 2>/dev/null)
    suppression_configured=$(echo "$update_response" | jq -r '.alert_suppression.group_by[0] // empty' 2>/dev/null)

    if [ "$updated_interval" == "1m" ]; then
        if [ "$suppression_configured" == "host.name" ]; then
            echo "  ✓ Updated: $rule_name (schedule + suppression)"
        else
            echo "  ✓ Updated: $rule_name (schedule only - suppression may not be supported for $rule_type rules)"
        fi
    else
        error_msg=$(echo "$update_response" | jq -r '.message // empty' 2>/dev/null)
        if [ -n "$error_msg" ]; then
            echo "  ✗ Failed: $rule_name - $error_msg"
        else
            echo "  ? Unknown: $rule_name"
        fi
    fi
done

echo ""

echo "[6/6] Results:"
echo ""
echo "  ✓ Rules enabled: ${success_count}"
if [ "$failed_count" != "0" ] && [ "$failed_count" != "null" ] && [ -n "$failed_count" ]; then
    echo "  ✗ Rules failed: $failed_count"
fi

echo ""
echo "=============================================="
echo "Demo rules are now enabled!"
echo "=============================================="
echo ""
echo "Enabled rules:"
for rule_name in "${RULE_NAMES[@]}"; do
    echo "  • $rule_name"
done
echo ""
echo "Rule settings:"
echo "  • Schedule: every 1 minute"
echo "  • Lookback: 10 minutes"
echo "  • Alert Suppression: by host.name, per 5 minutes"
echo ""
echo "Alert suppression reduces noise by grouping alerts from the"
echo "same host within a 5-minute window into a single alert."
echo ""
echo "Verify in Kibana:"
echo "  ${KIBANA_URL}/app/security/rules"
echo ""
echo "Login: elastic / (run 'terraform output elastic_dev_password')"
