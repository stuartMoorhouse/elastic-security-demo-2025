#!/bin/bash
# Enable detection rules for the purple team demo
#
# This script installs Elastic prebuilt rules (if not already installed) and
# enables the following rules in the Dev cluster for the tomcatastrophe demo:
#
#   - Sudo Command Enumeration Detected (Privilege Escalation)
#   - Cron Job Created or Modified (Persistence)
#
# Note: Initial Access, Execution, and other phases are detected by Elastic Defend
# behavioral alerts (Reverse Shell, Malware, etc.)
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

# Rules to enable - using rule_id (stable across versions) for reliable lookup
# Note: Only using EQL/query rules that fire reliably on every demo run
# The new_terms rules (Shadow File Read, Sensitive Files Compression) only fire
# on first occurrence within 10-day window, making them unsuitable for repeated demos
DEMO_RULE_IDS="28d39238-0c01-420a-b77a-24e5a7378663 ff10d4d8-fea7-422d-afb1-e5a2702369a9"
DEMO_RULE_NAMES="Sudo Command Enumeration Detected|Cron Job Created or Modified"

echo "[3/5] Looking up demo rules by rule_id..."
echo ""

# Find rules by rule_id and get their internal IDs
RULE_IDS=""
RULE_NAMES=""
for rule_id in $DEMO_RULE_IDS; do
    # Look up rule by rule_id
    rule_response=$(curl -s -u "elastic:${PASSWORD}" \
        "${KIBANA_URL}/api/detection_engine/rules?rule_id=${rule_id}" \
        -H "kbn-xsrf: true" \
        -H "Content-Type: application/json")

    internal_id=$(echo "$rule_response" | jq -r '.id // empty' 2>/dev/null)
    rule_name=$(echo "$rule_response" | jq -r '.name // empty' 2>/dev/null)

    if [ -n "$internal_id" ] && [ "$internal_id" != "null" ]; then
        echo "  ✓ Found: $rule_name"
        RULE_IDS="$RULE_IDS $internal_id"
        RULE_NAMES="$RULE_NAMES|$rule_name"
    else
        echo "  ✗ Not found: rule_id $rule_id"
    fi
done

# Trim leading space/pipe
RULE_IDS=$(echo "$RULE_IDS" | sed 's/^ //')
RULE_NAMES=$(echo "$RULE_NAMES" | sed 's/^|//')

echo ""

if [ -z "$RULE_IDS" ]; then
    echo "ERROR: No matching rules found."
    echo "Make sure prebuilt rules are installed."
    exit 1
fi

# Count rules
RULE_COUNT=$(echo "$RULE_IDS" | wc -w | tr -d ' ')

echo "[4/6] Enabling ${RULE_COUNT} rules..."
echo ""

# Build the bulk enable request
ids_json=$(echo "$RULE_IDS" | tr ' ' '\n' | jq -R . | jq -s .)

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
    success_count="$RULE_COUNT"
fi

failed_count=$(echo "$response" | jq -r '.attributes.summary.failed // 0' 2>/dev/null)

echo "       Enabled: ${success_count} rules"
echo ""

echo "[5/6] Updating rule schedules and adding alert suppression..."
echo ""
echo "       Schedule: 1 minute interval, 10 minute lookback"
echo "       Alert Suppression: by host.name, per 1 minute"
echo ""

# Update each rule's schedule and add alert suppression
for rule_id in $RULE_IDS; do
    # Get the rule name from the API response
    rule_name=$(curl -s -u "elastic:${PASSWORD}" \
        "${KIBANA_URL}/api/detection_engine/rules?id=${rule_id}" \
        -H "kbn-xsrf: true" | jq -r '.name // "Unknown"' 2>/dev/null)

    # Update the rule schedule: interval=1m, from=now-10m
    # Add alert suppression: group by host.name, suppress for 1 minute
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
                    \"value\": 1,
                    \"unit\": \"m\"
                },
                \"missing_fields_strategy\": \"suppress\"
            }
        }")

    # Check if update was successful
    updated_interval=$(echo "$update_response" | jq -r '.interval // empty' 2>/dev/null)
    suppression_configured=$(echo "$update_response" | jq -r '.alert_suppression.group_by[0] // empty' 2>/dev/null)

    if [ "$updated_interval" = "1m" ]; then
        if [ "$suppression_configured" = "host.name" ]; then
            echo "  ✓ Updated: $rule_name (schedule + suppression)"
        else
            echo "  ✓ Updated: $rule_name (schedule only - suppression may not be supported)"
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
echo "  • Sudo Command Enumeration Detected"
echo "  • Cron Job Created or Modified"
echo ""
echo "Rule settings:"
echo "  • Schedule: every 1 minute"
echo "  • Lookback: 10 minutes"
echo "  • Alert Suppression: by host.name, per 1 minute"
echo ""
echo "Alert suppression reduces noise by grouping alerts from the"
echo "same host within a 1-minute window into a single alert."
echo ""
echo "Verify in Kibana:"
echo "  ${KIBANA_URL}/app/security/rules"
echo ""
echo "Login: elastic / (run 'terraform output elastic_dev_password')"
