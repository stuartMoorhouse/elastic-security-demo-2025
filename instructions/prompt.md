# Create an Elastic Security demo

## Cloud reseources
### AWS
2 8GB RAM VMs running Ubuntu:
- red-01
- blue-01

## Elastic Cloud
Two 8 GB RAM Elastic Cloud Hosted instances:
- ec-local
- ec-dev

## GitHub
One forked detection-rules Repo for Elastic Security Detections as code. 

## Documentation and instructions
The following environment variables should be set on the local machine already: 
  - AWS_ACCESS_KEY_ID
  - AWS_SECRET_ACCESS_KEY                 
  - EC_API_KEY  

  The latest version of Elastic is 9.2. This is an example Elastic Cloud configuration in Terraform: 

  # Retrieve the latest stack pack version
data "ec_stack" "latest" {
  version_regex = "latest"
  region        = "us-east-1"
}

# Create an Elastic Cloud deployment
resource "ec_deployment" "example_minimal" {
  # Optional name.
  name = "my_example_deployment"

  region                 = "us-east-1"
  version                = data.ec_stack.latest.version
  deployment_template_id = "aws-io-optimized-v2"

  elasticsearch = {
    hot = {
      autoscaling = {}
    }
  }

  kibana = {}

  integrations_server = {}
}

## Creating the fork of https://github.com/elastic/detection-rules
Please use the terraform code in /example-terraform for guidance. We want a simplified version of this. 

The DaC workflow is:

Design a custom rule in the local-ec Kibana. 
Export the rule to the repo on my local machine. 
Commit the rule to GitHub, accept the pull request, so that GitHub then deploys it to dev-ec
The actual attack will detected with an Elastic Agent managed by Elastic Security on dev-ec. 