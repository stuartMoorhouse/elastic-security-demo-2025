#!/bin/bash
set -e

# Deploy tomcatastrophe.py to red-01 VM
# This script is run from the local machine after setup-red-vm.sh completes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get RED_VM_IP from environment or Terraform output
if [ -z "$RED_VM_IP" ]; then
    echo "RED_VM_IP not set, attempting to get from Terraform..."
    TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
    if [ -d "$TERRAFORM_DIR" ]; then
        RED_VM_IP=$(cd "$TERRAFORM_DIR" && terraform output -json red_vm 2>/dev/null | jq -r '.public_ip' 2>/dev/null)
    fi
    if [ -z "$RED_VM_IP" ] || [ "$RED_VM_IP" = "null" ]; then
        echo "ERROR: Could not determine RED_VM_IP"
        echo "Either set RED_VM_IP environment variable or run from a directory with Terraform state"
        exit 1
    fi
    echo "Found RED_VM_IP from Terraform: $RED_VM_IP"
fi

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_USER="${SSH_USER:-ubuntu}"

echo "=========================================="
echo "Deploying tomcatastrophe.py to red-01"
echo "=========================================="
echo "Target: ${SSH_USER}@${RED_VM_IP}"
echo "SSH Key: ${SSH_KEY}"
echo ""

# Wait for SSH to be available
echo "[1/3] Waiting for SSH access..."
for i in {1..30}; do
    if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes "${SSH_USER}@${RED_VM_IP}" "echo 'SSH ready'" 2>/dev/null; then
        echo "SSH connection established"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Could not establish SSH connection after 30 attempts"
        exit 1
    fi
    echo "Attempt $i/30 - waiting 10s..."
    sleep 10
done

# Copy tomcatastrophe.py to red-01
echo ""
echo "[2/3] Copying tomcatastrophe.py to red-01..."
scp -i "$SSH_KEY" -o StrictHostKeyChecking=no \
    "${SCRIPT_DIR}/tomcatastrophe.py" \
    "${SSH_USER}@${RED_VM_IP}:/home/ubuntu/scripts/"

# Make it executable
echo ""
echo "[3/3] Setting permissions..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "${SSH_USER}@${RED_VM_IP}" \
    "chmod +x /home/ubuntu/scripts/tomcatastrophe.py"

echo ""
echo "=========================================="
echo "Deployment complete!"
echo "=========================================="
echo ""
echo "To run the attack from red-01:"
echo "  ssh -i ${SSH_KEY} ${SSH_USER}@${RED_VM_IP}"
echo "  cd ~/scripts"
echo "  ./tomcatastrophe.py -t <BLUE_IP> -a <RED_IP>"
