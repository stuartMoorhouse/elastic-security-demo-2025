# AWS Outputs
output "red_vm" {
  description = "Red Team VM (red-01) connection information"
  value = {
    instance_id = aws_instance.red.id
    public_ip   = aws_instance.red.public_ip
    private_ip  = aws_instance.red.private_ip
    ssh_command = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.red.public_ip}"
  }
}

output "blue_vm" {
  description = "Blue Team VM (blue-01) connection information"
  value = {
    instance_id = aws_instance.blue.id
    public_ip   = aws_instance.blue.public_ip
    private_ip  = aws_instance.blue.private_ip
    ssh_command = "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.blue.public_ip}"
  }
}

# Elastic Cloud Outputs
output "elastic_local" {
  description = "Local Elastic Cloud deployment (for rule development)"
  value = {
    deployment_id      = ec_deployment.local.id
    elasticsearch_url  = ec_deployment.local.elasticsearch[0].https_endpoint
    kibana_url         = ec_deployment.local.kibana[0].https_endpoint
    elasticsearch_user = ec_deployment.local.elasticsearch_username
    cloud_id           = ec_deployment.local.elasticsearch[0].cloud_id
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
    elasticsearch_url  = ec_deployment.dev.elasticsearch[0].https_endpoint
    kibana_url         = ec_deployment.dev.kibana[0].https_endpoint
    elasticsearch_user = ec_deployment.dev.elasticsearch_username
    cloud_id           = ec_deployment.dev.elasticsearch[0].cloud_id
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
    full_name  = data.github_repository.detection_rules.full_name
    html_url   = data.github_repository.detection_rules.html_url
    clone_url  = data.github_repository.detection_rules.http_clone_url
    ssh_url    = data.github_repository.detection_rules.ssh_clone_url
  }
}

# Quick Start Commands
output "quick_start" {
  description = "Quick start commands for the purple team exercise"
  value = <<-EOT

    ELASTIC SECURITY DEMO - QUICK START
    ====================================

    1. SSH to Red Team VM (red-01):
       ${aws_instance.red.public_ip != "" ? "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.red.public_ip}" : "Instance starting..."}

    2. SSH to Blue Team VM (blue-01):
       ${aws_instance.blue.public_ip != "" ? "ssh -i ~/.ssh/id_rsa ubuntu@${aws_instance.blue.public_ip}" : "Instance starting..."}

    3. Access Kibana (Local - for rule development):
       ${ec_deployment.local.kibana[0].https_endpoint}
       User: ${ec_deployment.local.elasticsearch_username}
       Pass: Run 'terraform output elastic_local_password' to view

    4. Access Kibana (Dev - for purple team exercise):
       ${ec_deployment.dev.kibana[0].https_endpoint}
       User: ${ec_deployment.dev.elasticsearch_username}
       Pass: Run 'terraform output elastic_dev_password' to view

    5. Clone detection-rules fork:
       git clone ${data.github_repository.detection_rules.http_clone_url}

    Next Steps:
    - Follow instructions/red-vm.md to set up red-01
    - Follow instructions/blue-vm.md to set up blue-01
    - Follow instructions/demo-execution-script.md to run the demo

    To view sensitive outputs:
    - terraform output elastic_local_password
    - terraform output elastic_dev_password
  EOT
}
