# Deploy Elastic Agent to blue-01 VM
# This resource runs after Elastic Cloud dev deployment and blue-01 VM are ready

resource "null_resource" "deploy_elastic_agent" {
  # Ensure this runs after the dev deployment and blue VM are ready
  depends_on = [
    ec_deployment.dev,
    aws_instance.blue
  ]

  # Wait for blue-01 to finish initialization (user_data script completion)
  # and for Elastic Cloud to be fully available
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "=========================================="
      echo "Waiting for blue-01 VM to complete initialization..."
      echo "=========================================="

      # Wait for SSH to be available and setup to complete
      max_attempts=60
      attempt=0

      while [ $attempt -lt $max_attempts ]; do
        if ssh -i ~/.ssh/id_ed25519 -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@${aws_instance.blue.public_ip} "test -f /home/ubuntu/blue-vm-info.txt" 2>/dev/null; then
          echo "✓ Blue-01 initialization complete"
          break
        fi

        attempt=$((attempt + 1))
        if [ $attempt -eq $max_attempts ]; then
          echo "ERROR: blue-01 did not complete initialization in time"
          exit 1
        fi

        echo "Waiting for blue-01 setup to complete... (attempt $attempt/$max_attempts)"
        sleep 10
      done

      echo ""
      echo "=========================================="
      echo "Waiting for Elastic Cloud to be fully ready..."
      echo "=========================================="

      # Wait for Kibana to be responsive
      attempt=0
      while [ $attempt -lt 30 ]; do
        if curl -s -u "elastic:${ec_deployment.dev.elasticsearch_password}" \
             "${ec_deployment.dev.kibana.https_endpoint}/api/status" >/dev/null 2>&1; then
          echo "✓ Kibana is ready"
          break
        fi

        attempt=$((attempt + 1))
        if [ $attempt -eq 30 ]; then
          echo "ERROR: Kibana did not become ready in time"
          exit 1
        fi

        echo "Waiting for Kibana to be ready... (attempt $attempt/30)"
        sleep 10
      done

      echo ""
      echo "=========================================="
      echo "Deploying Elastic Agent to blue-01..."
      echo "=========================================="
      echo ""

      # Execute the deployment script with environment variables and clean PATH
      cd ${path.module}/../scripts

      PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin" \
      KIBANA_URL="${ec_deployment.dev.kibana.https_endpoint}" \
      ELASTIC_USER="elastic" \
      ELASTIC_PASSWORD="${ec_deployment.dev.elasticsearch_password}" \
      DEPLOYMENT_NAME="${ec_deployment.dev.name}" \
      DEPLOYMENT_ID="${ec_deployment.dev.id}" \
      ELASTICSEARCH_URL="${ec_deployment.dev.elasticsearch.https_endpoint}" \
      BLUE_VM_IP="${aws_instance.blue.public_ip}" \
      SSH_KEY="$HOME/.ssh/id_ed25519" \
      AGENT_VERSION="9.2.0" \
      ./deploy-elastic-agent.sh

      echo ""
      echo "=========================================="
      echo "Elastic Agent deployment complete!"
      echo "=========================================="
    EOT
  }

  # Trigger re-deployment if any of these values change
  triggers = {
    deployment_id = ec_deployment.dev.id
    blue_vm_id    = aws_instance.blue.id
    script_hash   = filemd5("${path.module}/../scripts/deploy-elastic-agent.sh")
  }
}

# Output to confirm agent deployment
output "elastic_agent_deployment" {
  description = "Elastic Agent deployment status"
  value = {
    deployed_to_vm     = aws_instance.blue.public_ip
    managed_by         = ec_deployment.dev.name
    kibana_fleet_url   = "${ec_deployment.dev.kibana.https_endpoint}/app/fleet"
    verification_command = "ssh -i ~/.ssh/id_ed25519 ubuntu@${aws_instance.blue.public_ip} 'sudo elastic-agent status'"
  }

  depends_on = [null_resource.deploy_elastic_agent]
}
