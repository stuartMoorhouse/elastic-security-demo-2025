# AWS Outputs - Disabled for Detection as Code demo
# Uncomment when AWS VMs are re-enabled in main.tf
# output "red_vm" {
#   description = "Red Team VM (red-01) connection information"
#   value = {
#     instance_id = aws_instance.red.id
#     public_ip   = aws_instance.red.public_ip
#     private_ip  = aws_instance.red.private_ip
#     ssh_command = "ssh -i ~/.ssh/id_ed25519 ubuntu@${aws_instance.red.public_ip}"
#   }
# }
#
# output "blue_vm" {
#   description = "Blue Team VM (blue-01) connection information"
#   value = {
#     instance_id = aws_instance.blue.id
#     public_ip   = aws_instance.blue.public_ip
#     private_ip  = aws_instance.blue.private_ip
#     ssh_command = "ssh -i ~/.ssh/id_ed25519 ubuntu@${aws_instance.blue.public_ip}"
#   }
# }

# Elastic Cloud Outputs
output "elastic_local" {
  description = "Local Elastic Cloud deployment (for rule development)"
  value = {
    deployment_id      = ec_deployment.local.id
    elasticsearch_url  = ec_deployment.local.elasticsearch.https_endpoint
    kibana_url         = ec_deployment.local.kibana.https_endpoint
    elasticsearch_user = ec_deployment.local.elasticsearch_username
    cloud_id           = ec_deployment.local.elasticsearch.cloud_id
  }
  sensitive = false
}

output "elastic_local_password" {
  description = "Local Elastic deployment password (sensitive)"
  value       = ec_deployment.local.elasticsearch_password
  sensitive   = true
}

output "elastic_dev" {
  description = "Development Elastic Cloud deployment (for purple team exercise)"
  value = {
    deployment_id      = ec_deployment.dev.id
    elasticsearch_url  = ec_deployment.dev.elasticsearch.https_endpoint
    kibana_url         = ec_deployment.dev.kibana.https_endpoint
    elasticsearch_user = ec_deployment.dev.elasticsearch_username
    cloud_id           = ec_deployment.dev.elasticsearch.cloud_id
  }
  sensitive = false
}

output "elastic_dev_password" {
  description = "Development Elastic deployment password (sensitive)"
  value       = ec_deployment.dev.elasticsearch_password
  sensitive   = true
}

# GitHub Outputs
output "github_repository" {
  description = "Forked detection-rules repository information"
  value = {
    full_name = data.github_repository.detection_rules.full_name
    html_url  = data.github_repository.detection_rules.html_url
    clone_url = data.github_repository.detection_rules.http_clone_url
    ssh_url   = data.github_repository.detection_rules.ssh_clone_url
  }
}

# Quick Start Commands
output "quick_start" {
  description = "Quick start commands for Detection as Code demo"
  value       = <<-EOT

    ELASTIC SECURITY DEMO - DETECTION AS CODE
    ==========================================

    1. Access Kibana (Local - for rule development):
       ${ec_deployment.local.kibana.https_endpoint}
       User: ${ec_deployment.local.elasticsearch_username}
       Pass: Run 'terraform output elastic_local_password' to view

    2. Access Kibana (Dev - for demo deployment):
       ${ec_deployment.dev.kibana.https_endpoint}
       User: ${ec_deployment.dev.elasticsearch_username}
       Pass: Run 'terraform output elastic_dev_password' to view

    3. Clone detection-rules fork:
       git clone ${data.github_repository.detection_rules.http_clone_url}

    Next Steps:
    - Set up detection-rules CLI on your local machine (see instructions/local-setup.md)
    - Create and test detection rules in the Local environment
    - Push rules to GitHub and deploy via CI/CD to Dev environment
    - Monitor the deployment workflow in GitHub Actions

    To view sensitive outputs:
    - terraform output elastic_local_password
    - terraform output elastic_dev_password
  EOT
}
