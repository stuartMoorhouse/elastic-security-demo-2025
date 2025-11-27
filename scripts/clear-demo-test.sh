#!/bin/bash
# Clear demo test artifacts from both VMs
#
# This script cleans up artifacts from previous tomcatastrophe runs so you can
# start fresh for each demo. Run this BEFORE running tomcatastrophe.py.
#
# What it cleans:
#   On red-01 (attacker):
#     - Kill any running msfconsole processes
#     - Kill any netcat listeners
#     - Remove temporary resource files
#
#   On blue-01 (target):
#     - Remove persistence cron jobs
#     - Remove staged data files
#     - Clean up /tmp artifacts
#
# Usage:
#   ./clear-demo-test.sh
#
# Prerequisites:
#   - Terraform deployed (to get VM IPs)
#   - SSH access to both VMs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

echo "=============================================="
echo "Clear Demo Test Artifacts"
echo "=============================================="
echo ""

# Get VM IPs from Terraform
cd "$TERRAFORM_DIR"

echo "[1/4] Getting VM information from Terraform..."
RED_IP=$(terraform output -json red_vm | jq -r '.public_ip')
BLUE_IP=$(terraform output -json blue_vm | jq -r '.public_ip')
SSH_KEY=$(terraform output -json red_vm | jq -r '.ssh_command' | grep -o '\-i [^ ]*' | cut -d' ' -f2)

if [ -z "$RED_IP" ] || [ "$RED_IP" == "null" ]; then
    echo "ERROR: Could not get red VM IP. Is the infrastructure deployed?"
    exit 1
fi

echo "       Red VM (attacker): $RED_IP"
echo "       Blue VM (target):  $BLUE_IP"
echo "       SSH Key: $SSH_KEY"
echo ""

# Clean up red-01 (attacker)
echo "[2/4] Cleaning red-01 (attacker)..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${RED_IP}" bash <<'EOF'
echo "  - Killing msfconsole processes..."
pkill -9 msfconsole 2>/dev/null || true

echo "  - Killing netcat listeners..."
pkill -9 -f 'nc.*-l.*444' 2>/dev/null || true

echo "  - Removing temporary files..."
rm -f /tmp/tomcatastrophe.rc 2>/dev/null || true
rm -f /tmp/tomcatastrophe_abort 2>/dev/null || true

echo "  - Done"
EOF

echo ""

# Clean up blue-01 (target)
echo "[3/4] Cleaning blue-01 (target)..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${BLUE_IP}" bash <<'EOF'
echo "  - Removing persistence cron jobs..."
sudo crontab -r 2>/dev/null || true

echo "  - Removing staged data..."
sudo rm -rf /tmp/.staging 2>/dev/null || true
sudo rm -f /tmp/data.tar.gz 2>/dev/null || true

echo "  - Cleaning shell history artifacts..."
# Don't actually clear history, just remove any test artifacts

echo "  - Verifying Tomcat is running..."
if systemctl is-active --quiet tomcat; then
    echo "    Tomcat: running"
else
    echo "    Tomcat: NOT running - restarting..."
    sudo systemctl restart tomcat
fi

echo "  - Done"
EOF

echo ""

# Summary
echo "[4/4] Cleanup complete!"
echo ""
echo "=============================================="
echo "Demo environment is ready for a fresh run"
echo "=============================================="
echo ""
echo "Next steps:"
echo "  1. SSH to red-01: ssh -i $SSH_KEY ubuntu@$RED_IP"
echo "  2. Run the attack: ./scripts/tomcatastrophe.py -t 10.0.1.67 -a 10.0.1.119 --fast"
echo ""
