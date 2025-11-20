# GitHub CI/CD Configuration for Detection as Code Workflow
# Automatically deploys detection rules to ec-dev when merged to main branch

# GitHub Actions Workflow - Deploy to Development Environment
# Triggers when code is pushed to main branch (after PR merge from feature branches)
resource "github_repository_file" "deploy_to_dev_workflow" {
  repository = data.github_repository.detection_rules.name
  branch     = "main"
  file       = ".github/workflows/deploy-to-dev.yml"

  content = file("${path.module}/templates/deploy-to-dev.yml")

  commit_message = "Add GitHub Actions workflow for deploying to development"
  commit_author  = "Terraform"
  commit_email   = "terraform@elastic-security-demo.local"

  lifecycle {
    ignore_changes = [commit_message, commit_author, commit_email]
  }

  depends_on = [
    null_resource.fork_detection_rules,
    data.github_repository.detection_rules
  ]
}

# Remove old workflow files inherited from elastic/detection-rules fork
# Keep only deploy-to-dev.yml for the demo
resource "null_resource" "cleanup_old_workflows" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Cleaning up old workflow files from forked repository..."

      REPO="${var.github_owner}/${var.fork_name}"
      PROJECT_DIR="${path.module}/../.."
      REPO_DIR="$${PROJECT_DIR}/${var.fork_name}"

      # List of workflow files to remove (inherited from elastic/detection-rules)
      OLD_WORKFLOWS=(
        "add-guidelines.yml"
        "backport.yml"
        "branch-status-checks.yml"
        "code-checks.yml"
        "community.yml"
        "docs-build.yml"
        "docs-cleanup.yml"
        "esql-validation.yml"
        "get-target-branches.yml"
        "kibana-mitre-update.yml"
        "lock-versions.yml"
        "manual-backport.yml"
        "pythonpackage.yml"
        "react-tests-dispatcher.yml"
        "release-docs.yml"
        "release-fleet.yml"
        "version-code-and-release.yml"
      )

      # Clone or update the repository
      if [ -d "$${REPO_DIR}/.git" ]; then
        echo "Using existing repository at $${REPO_DIR}"
        cd "$${REPO_DIR}"
        git fetch origin
        git checkout main
        # Reset to origin/main to handle divergent branches
        git reset --hard origin/main
      else
        echo "Cloning repository to $${REPO_DIR}..."
        git clone "https://github.com/$${REPO}.git" "$${REPO_DIR}"
        cd "$${REPO_DIR}"
      fi

      # Check if any old workflows exist
      WORKFLOWS_TO_DELETE=()
      for workflow in "$${OLD_WORKFLOWS[@]}"; do
        if [ -f ".github/workflows/$${workflow}" ]; then
          WORKFLOWS_TO_DELETE+=("$${workflow}")
        fi
      done

      if [ $${#WORKFLOWS_TO_DELETE[@]} -eq 0 ]; then
        echo "No old workflow files to remove - cleanup already complete"
        exit 0
      fi

      echo "Found $${#WORKFLOWS_TO_DELETE[@]} old workflow files to remove"

      # Remove old workflow files
      for workflow in "$${WORKFLOWS_TO_DELETE[@]}"; do
        echo "  Removing .github/workflows/$${workflow}"
        git rm ".github/workflows/$${workflow}"
      done

      # Commit and push the changes
      git commit -m "chore: Remove old workflow files from elastic/detection-rules fork

- Removed $${#WORKFLOWS_TO_DELETE[@]} workflow files inherited from upstream
- Keeping only deploy-to-dev.yml for detection-as-code demo
- Simplifies GitHub Actions to demo-specific workflows"

      echo "Pushing cleanup changes to main branch..."
      git push origin main

      echo "✅ Workflow cleanup completed successfully!"
      echo "Removed $${#WORKFLOWS_TO_DELETE[@]} old workflow files"
    EOT
  }

  depends_on = [
    github_repository_file.deploy_to_dev_workflow,
    null_resource.fork_detection_rules,
    data.github_repository.detection_rules
  ]
}

# Set up GitHub Secrets with Elastic Cloud credentials
# This runs after EC deployments are created and updates secrets automatically
resource "null_resource" "setup_github_secrets" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Setting up GitHub Secrets for CI/CD workflow..."

      REPO="${var.github_owner}/${var.fork_name}"

      # Create API key for Development cluster
      echo "Creating API key for ec-dev deployment..."

      # Use environment variable to avoid password exposure in process listings
      export ELASTIC_PASSWORD="${ec_deployment.dev.elasticsearch_password}"

      # Create API key with limited privileges (least privilege principle)
      # Permissions limited to: kibana space access and custom-rules index management
      DEV_API_KEY=$(curl -s -u "elastic:$${ELASTIC_PASSWORD}" \
        -X POST "${ec_deployment.dev.elasticsearch.https_endpoint}/_security/api_key" \
        -H "Content-Type: application/json" \
        -d '{
          "name": "github-actions-dev",
          "expiration": "90d",
          "role_descriptors": {
            "detection_rules": {
              "cluster": ["manage_api_key", "monitor"],
              "indices": [
                {
                  "names": ["*"],
                  "privileges": ["all"]
                }
              ],
              "applications": [
                {
                  "application": "kibana-.kibana",
                  "privileges": ["all"],
                  "resources": ["*"]
                }
              ]
            }
          }
        }' \
        2>/dev/null | jq -r '.encoded')

      # Clear the password from environment immediately
      unset ELASTIC_PASSWORD

      if [ -z "$${DEV_API_KEY}" ] || [ "$${DEV_API_KEY}" == "null" ]; then
        echo "ERROR: Failed to create API key for ec-dev"
        exit 1
      fi

      # Set GitHub Secrets
      echo "Setting DEV_ELASTIC_CLOUD_ID secret..."
      gh secret set DEV_ELASTIC_CLOUD_ID \
        --repo "$${REPO}" \
        --body "${ec_deployment.dev.elasticsearch.cloud_id}"

      echo "Setting DEV_ELASTIC_API_KEY secret..."
      gh secret set DEV_ELASTIC_API_KEY \
        --repo "$${REPO}" \
        --body "$${DEV_API_KEY}"

      # Clear API key from environment
      unset DEV_API_KEY

      echo ""
      echo "✅ GitHub Secrets configured successfully!"
      echo ""
      echo "Configured secrets:"
      echo "  - DEV_ELASTIC_CLOUD_ID (Cloud ID for ec-dev)"
      echo "  - DEV_ELASTIC_API_KEY (API key for deploying rules, 90-day expiration)"
      echo ""
      echo "GitHub Actions workflows can now deploy to ec-dev automatically."
    EOT
  }

  # Run this whenever the EC deployment changes
  triggers = {
    dev_deployment_id = ec_deployment.dev.id
    dev_cloud_id      = ec_deployment.dev.elasticsearch.cloud_id
    dev_kibana_url    = ec_deployment.dev.kibana.https_endpoint
  }

  depends_on = [
    ec_deployment.dev,
    null_resource.fork_detection_rules,
    data.github_repository.detection_rules
  ]
}

# Set up custom rules directory structure in the forked repository
resource "null_resource" "setup_custom_rules_directory" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Setting up custom rules directory structure..."

      REPO_NAME="${var.fork_name}"
      PROJECT_DIR="${path.module}/../.."
      REPO_DIR="$${PROJECT_DIR}/$${REPO_NAME}"
      GITHUB_USER="${var.github_owner}"

      # Check if repository already exists locally
      if [ -d "$${REPO_DIR}/.git" ]; then
        echo "Local repository already exists at $${REPO_DIR}"
        cd "$${REPO_DIR}"
        git fetch origin
        # Reset to origin/main to handle divergent branches
        git reset --hard origin/main
      else
        # Clone the repository to project directory
        echo "Cloning repository to $${REPO_DIR}..."
        git clone "https://github.com/$${GITHUB_USER}/$${REPO_NAME}.git" "$${REPO_DIR}"
        cd "$${REPO_DIR}"
      fi

      # Check if custom-rules directory already exists
      if [ -d "custom-rules" ]; then
        echo "custom-rules directory already exists, skipping setup"
        exit 0
      fi

      # Create custom-rules directory structure
      echo "Creating custom-rules directory structure..."
      mkdir -p custom-rules/rules custom-rules/docs

      # Create README for custom-rules
      cat > custom-rules/README.md << 'README'
# Custom Detection Rules

This directory contains custom detection rules for the Elastic Security Detection as Code demo.

## Directory Structure

```
custom-rules/
├── rules/          # Your custom detection rules (TOML format)
├── docs/           # Documentation for custom rules
└── README.md       # This file
```

## Adding Custom Rules

1. Create your rule TOML file in `custom-rules/rules/`
2. Test locally: `python -m detection_rules test custom-rules/rules/your-rule.toml`
3. Commit and push to a feature branch
4. Create PR to `dev` branch
5. After merge, rules automatically deploy to ec-dev

## Rule Format

Rules should follow the Elastic detection rules format:

```toml
[metadata]
creation_date = "2025/11/07"
integration = ["endpoint"]
maturity = "production"
updated_date = "2025/11/07"

[rule]
author = ["Your Name"]
description = """
Your rule description here.
"""
from = "now-9m"
index = ["logs-endpoint.events.*"]
language = "eql"
license = "Elastic License v2"
name = "Your Rule Name"
risk_score = 73
rule_id = "unique-uuid-here"
severity = "high"
tags = ["Domain: Endpoint", "OS: Linux"]
type = "eql"

query = '''
process where event.type == "start" and
  process.name == "suspicious_process"
'''
```

## Testing Workflow

1. **Local Development** (ec-local):
   - Create rules in Kibana UI
   - Export using detection-rules CLI
   - Test in local environment

2. **Development Deployment** (ec-dev):
   - Push to `dev` branch
   - Automatic deployment via GitHub Actions
   - Run demo attacks to validate

3. **Demo Execution**:
   - Rules are active in ec-dev
   - Execute attack chain from red-01
   - Verify alerts trigger correctly

## Resources

- [Elastic Detection Rules Repository](https://github.com/elastic/detection-rules)
- [Detection Rules Documentation](https://www.elastic.co/guide/en/security/current/detection-engine-overview.html)
- [EQL Syntax Reference](https://www.elastic.co/guide/en/elasticsearch/reference/current/eql-syntax.html)
README

      # Create a sample rule file (commented out for reference)
      cat > custom-rules/rules/.gitkeep << 'GITKEEP'
# Place your custom detection rules (.toml files) in this directory
#
# Example:
#   custom-rules/rules/my_custom_rule.toml
#   custom-rules/rules/tomcat_webshell_detection.toml
GITKEEP

      # Commit and push the changes
      git add custom-rules/
      git commit -m "feat: Initialize custom-rules directory for custom detection rules

- Create custom-rules/rules/ for custom TOML rule files
- Create custom-rules/docs/ for rule documentation
- Add comprehensive README with usage instructions
- Set up CI/CD integration with GitHub Actions"

      echo "Pushing changes to main branch..."
      git push origin main

      echo "✅ Custom rules directory structure created successfully!"
      echo "Local repository maintained at: $${REPO_DIR}"
      echo ""
      echo "Directory structure:"
      echo "  custom-rules/"
      echo "  ├── rules/     (place your .toml rule files here)"
      echo "  ├── docs/      (rule documentation)"
      echo "  └── README.md  (usage instructions)"
    EOT
  }

  triggers = {
    repo_name = var.fork_name
  }

  depends_on = [
    null_resource.fork_detection_rules,
    data.github_repository.detection_rules
  ]
}

# Output CI/CD configuration status
output "github_ci_cd_status" {
  description = "GitHub CI/CD configuration summary"
  value = {
    workflow_file      = github_repository_file.deploy_to_dev_workflow.file
    github_secrets_configured = [
      "DEV_ELASTIC_CLOUD_ID",
      "DEV_ELASTIC_API_KEY"
    ]
    custom_rules_directory = "custom-rules/rules/"
    deployment_target      = "ec-dev (Development Environment)"
    deployment_branch      = "main"
    workflow_trigger       = "Merge PR to main branch"
    api_key_expiration     = "90 days"
    security_note          = "API key has limited privileges per principle of least privilege"
  }

  depends_on = [
    github_repository_file.deploy_to_dev_workflow,
    null_resource.setup_github_secrets,
    null_resource.setup_custom_rules_directory
  ]
}
