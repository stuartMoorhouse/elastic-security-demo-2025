#!/bin/bash

# Export all required environment variables from terraform outputs
export KIBANA_URL=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.kibana_url')
export ELASTIC_PASSWORD=$(cd terraform && terraform output -raw elastic_dev_password)
export DEPLOYMENT_NAME=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.deployment_name')
export DEPLOYMENT_ID=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.deployment_id')
export ELASTICSEARCH_URL=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.elasticsearch_url')
export BLUE_VM_IP=$(cd terraform && terraform output -json blue_vm | jq -r '.value.public_ip')
export ELASTIC_VERSION=$(cd terraform && terraform output -json elastic_dev | jq -r '.value.version')

echo "Environment variables set:"
echo "  KIBANA_URL: $KIBANA_URL"
echo "  ELASTIC_PASSWORD: [REDACTED]"
echo "  DEPLOYMENT_NAME: $DEPLOYMENT_NAME"
echo "  DEPLOYMENT_ID: $DEPLOYMENT_ID"
echo "  ELASTICSEARCH_URL: $ELASTICSEARCH_URL"
echo "  BLUE_VM_IP: $BLUE_VM_IP"
echo "  ELASTIC_VERSION: $ELASTIC_VERSION"
