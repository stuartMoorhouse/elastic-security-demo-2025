# Retrieve the latest Elastic Stack version
data "ec_stack" "latest" {
  version_regex = var.elastic_version
  region        = var.ec_region
}

# Local Elastic Cloud deployment (for rule development)
resource "ec_deployment" "local" {
  name                   = "${var.project_name}-local"
  region                 = var.ec_region
  version                = data.ec_stack.latest.version
  deployment_template_id = var.deployment_template_id

  elasticsearch = {
    hot = {
      size        = var.elasticsearch_size
      zone_count  = var.elasticsearch_zone_count
      autoscaling = {}
    }
  }

  kibana = {
    size       = var.kibana_size
    zone_count = var.kibana_zone_count
  }

  integrations_server = {
    size       = var.integrations_server_size
    zone_count = var.integrations_server_zone_count
  }

  tags = {
    environment = "local"
    purpose     = "rule-development"
    project     = var.project_name
  }
}

# Development Elastic Cloud deployment (for demo attacks)
resource "ec_deployment" "dev" {
  name                   = "${var.project_name}-dev"
  region                 = var.ec_region
  version                = data.ec_stack.latest.version
  deployment_template_id = var.deployment_template_id

  elasticsearch = {
    hot = {
      size        = var.elasticsearch_size
      zone_count  = var.elasticsearch_zone_count
      autoscaling = {}
    }
  }

  kibana = {
    size       = var.kibana_size
    zone_count = var.kibana_zone_count
  }

  integrations_server = {
    size       = var.integrations_server_size
    zone_count = var.integrations_server_zone_count
  }

  tags = {
    environment = "development"
    purpose     = "demo-target"
    project     = var.project_name
  }
}

# Automatically create API key and environment variables for detection-rules CLI
resource "null_resource" "setup_detection_rules" {
  depends_on = [ec_deployment.local]

  # Only run when the local deployment changes
  triggers = {
    deployment_id = ec_deployment.local.id
  }

  provisioner "local-exec" {
    command     = "../scripts/setup-detection-rules.sh"
    working_dir = path.module

    # Pass values directly instead of using terraform output (which isn't available during apply)
    environment = {
      LOCAL_CLOUD_ID             = ec_deployment.local.elasticsearch.cloud_id
      LOCAL_KIBANA_URL           = ec_deployment.local.kibana.https_endpoint
      LOCAL_ELASTICSEARCH_URL    = ec_deployment.local.elasticsearch.https_endpoint
      LOCAL_ELASTICSEARCH_USER   = ec_deployment.local.elasticsearch_username
      LOCAL_ELASTICSEARCH_PASSWORD = ec_deployment.local.elasticsearch_password
    }
  }
}

# Ingest test data (true-positive.json and true-negative.json) into Local Elasticsearch
resource "null_resource" "ingest_test_data" {
  depends_on = [null_resource.setup_detection_rules]

  # Only run when the local deployment changes
  triggers = {
    deployment_id = ec_deployment.local.id
  }

  provisioner "local-exec" {
    command     = "scripts/ingest-test-data.sh"
    working_dir = "${path.module}/.."
  }
}

# Automatically deploy Elastic Agent to blue-01 VM after infrastructure is ready
resource "null_resource" "deploy_elastic_agent" {
  depends_on = [
    ec_deployment.dev,
    aws_instance.blue
  ]

  # Re-run if dev deployment or blue VM changes
  triggers = {
    deployment_id = ec_deployment.dev.id
    blue_vm_id    = aws_instance.blue.id
  }

  provisioner "local-exec" {
    command     = "../scripts/deploy-elastic-agent.sh"
    working_dir = path.module

    environment = {
      KIBANA_URL         = ec_deployment.dev.kibana.https_endpoint
      ELASTIC_PASSWORD   = ec_deployment.dev.elasticsearch_password
      DEPLOYMENT_NAME    = ec_deployment.dev.name
      DEPLOYMENT_ID      = ec_deployment.dev.id
      ELASTICSEARCH_URL  = ec_deployment.dev.elasticsearch.https_endpoint
      BLUE_VM_IP         = aws_instance.blue.public_ip
      ELASTIC_VERSION    = ec_deployment.dev.version
      SSH_KEY            = pathexpand(var.ssh_private_key_path)
    }
  }
}
