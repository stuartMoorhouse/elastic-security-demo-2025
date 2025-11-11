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
  }
}
