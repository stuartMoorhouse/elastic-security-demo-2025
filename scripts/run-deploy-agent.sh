#!/bin/bash
set -e

# Get values from terraform
cd terraform

KIBANA_URL=$(terraform output -json elastic_dev | jq -r '.kibana_url')
ELASTIC_PASSWORD=$(terraform output -raw elastic_dev_password)
DEPLOYMENT_NAME=$(terraform output -json elastic_dev | jq -r '.deployment_name')
DEPLOYMENT_ID=$(terraform output -json elastic_dev | jq -r '.deployment_id')
ELASTICSEARCH_URL=$(terraform output -json elastic_dev | jq -r '.elasticsearch_url')
BLUE_VM_IP=$(terraform output -json blue_vm | jq -r '.public_ip')
ELASTIC_VERSION=$(terraform output -json elastic_dev | jq -r '.version')

cd ..

# Export and run script
export KIBANA_URL
export ELASTIC_PASSWORD  
export DEPLOYMENT_NAME
export DEPLOYMENT_ID
export ELASTICSEARCH_URL
export BLUE_VM_IP
export ELASTIC_VERSION

./scripts/deploy-elastic-agent.sh
