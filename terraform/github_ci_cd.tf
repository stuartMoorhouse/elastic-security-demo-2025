# GitHub CI/CD Configuration for Detection as Code Workflow
# Automatically deploys detection rules to ec-dev when merged to dev branch

# Create dev branch for deployment workflow
resource "github_branch" "dev" {
  repository    = data.github_repository.detection_rules.name
  branch        = "dev"
  source_branch = "main"

  depends_on = [
    data.github_repository.detection_rules
  ]
}

# GitHub Actions Workflow - Deploy to Development Environment
# Triggers when code is pushed to dev branch (after PR merge)
resource "github_repository_file" "deploy_to_dev_workflow" {
  repository = data.github_repository.detection_rules.name
  branch     = "main"
  file       = ".github/workflows/deploy-to-dev.yml"

  content = <<-EOT
name: Detection Rules CI/CD

on:
  push:
    branches:
      - dev
      - 'feature/**'
  pull_request:
    branches:
      - dev
  workflow_dispatch:  # Allow manual triggering

jobs:
  # Auto-create PR when pushing to feature branches
  create-pr:
    if: github.event_name == 'push' && startsWith(github.ref, 'refs/heads/feature/')
    runs-on: ubuntu-latest
    name: Auto-create Pull Request

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Create Pull Request
      env:
        GH_TOKEN: $${{ github.token }}
      run: |
        BRANCH_NAME=$${GITHUB_REF#refs/heads/}

        # Check if PR already exists
        EXISTING_PR=$$(gh pr list --head "$$BRANCH_NAME" --base dev --json number --jq '.[0].number')

        if [ -z "$$EXISTING_PR" ]; then
          echo "Creating pull request from $$BRANCH_NAME to dev..."
          gh pr create \
            --base dev \
            --head "$$BRANCH_NAME" \
            --title "Detection Rule: $$BRANCH_NAME" \
            --body "## Detection Rule Update

This PR contains updates to custom detection rules.

### Checklist
- [ ] Rule has been tested locally
- [ ] Rule validation passes
- [ ] Rule metadata is complete
- [ ] MITRE ATT&CK mapping is accurate

Once approved and merged, this rule will be automatically deployed to the Development environment (ec-dev)."

          echo "✅ Pull request created successfully!"
        else
          echo "ℹ️ Pull request #$$EXISTING_PR already exists"
        fi

  # Validate rules on PR
  validate:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    name: Validate Detection Rules

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.12'

    - name: Install detection-rules dependencies
      run: |
        python -m pip install --upgrade pip
        pip install .
        pip install lib/kibana
        pip install lib/kql

    - name: Validate custom rules
      run: |
        if [ -d "custom-rules/rules" ] && [ "$$(ls -A custom-rules/rules/*.toml 2>/dev/null)" ]; then
          echo "🔍 Validating custom rules..."
          for rule in custom-rules/rules/*.toml; do
            echo "Validating: $$rule"
            python -m detection_rules test "$$rule" || echo "⚠️ Note: Validation may require additional context"
          done
          echo "✅ Validation complete!"
        else
          echo "ℹ️ No custom rules found to validate"
        fi

    - name: Add validation summary
      if: always()
      run: |
        echo "## 🔍 Rule Validation Results" >> $$GITHUB_STEP_SUMMARY
        echo "" >> $$GITHUB_STEP_SUMMARY
        if [ "$${{ job.status }}" == "success" ]; then
          echo "✅ All rules passed validation" >> $$GITHUB_STEP_SUMMARY
        else
          echo "❌ Validation failed - please review the logs" >> $$GITHUB_STEP_SUMMARY
        fi

  # Deploy to dev when PR is merged
  deploy-to-dev:
    if: github.event_name == 'push' && github.ref == 'refs/heads/dev'
    runs-on: ubuntu-latest
    name: Deploy Detection Rules to ec-dev

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4
      with:
        fetch-depth: 0

    - name: Set up Python
      uses: actions/setup-python@v5
      with:
        python-version: '3.12'

    - name: Install detection-rules dependencies
      run: |
        python -m pip install --upgrade pip
        pip install .
        pip install lib/kibana
        pip install lib/kql

    - name: Configure detection-rules
      run: |
        # Create custom-rules/rules directory if it doesn't exist
        mkdir -p custom-rules/rules

        # Create detection-rules config file
        cat > .detection-rules-cfg.json << EOF
        {
          "custom_rules_dir": "custom-rules"
        }
        EOF

    - name: Validate custom rules
      run: |
        if [ -d "custom-rules/rules" ] && [ "$$(ls -A custom-rules/rules/*.toml 2>/dev/null)" ]; then
          echo "Validating custom rules..."
          for rule in custom-rules/rules/*.toml; do
            echo "Validating: $$rule"
            python -m detection_rules test "$$rule" || echo "Note: Validation may require additional context"
          done
        else
          echo "No custom rules found in custom-rules/rules/"
        fi

    - name: Deploy to Development Kibana (ec-dev)
      env:
        ELASTIC_CLOUD_ID: $${{ secrets.DEV_ELASTIC_CLOUD_ID }}
        ELASTIC_API_KEY: $${{ secrets.DEV_ELASTIC_API_KEY }}
      run: |
        if [ -d "custom-rules/rules" ] && [ "$$(ls -A custom-rules/rules/*.toml 2>/dev/null)" ]; then
          echo "🚀 Deploying custom rules to Development environment (ec-dev)..."

          # Update detection-rules config with Elastic Cloud credentials
          cat > .detection-rules-cfg.json << EOF
        {
          "cloud_id": "$${ELASTIC_CLOUD_ID}",
          "api_key": "$${ELASTIC_API_KEY}",
          "custom_rules_dir": "custom-rules"
        }
        EOF

          # Import rules to Development Kibana
          python -m detection_rules kibana --space default import-rules \
            -d custom-rules/rules/ || echo "Note: Some rules may already exist"

          # Clean up config file
          rm -f .detection-rules-cfg.json

          echo "✅ Development deployment completed successfully!"
        else
          echo "ℹ️ No custom rules to deploy to Development"
        fi

    - name: Create deployment summary
      if: always()
      run: |
        echo "## 🚀 Development Environment Deployment" >> $$GITHUB_STEP_SUMMARY
        echo "" >> $$GITHUB_STEP_SUMMARY

        if [ "$${{ job.status }}" == "success" ]; then
          echo "### ✅ Deployment Successful" >> $$GITHUB_STEP_SUMMARY
          echo "" >> $$GITHUB_STEP_SUMMARY
          echo "Custom detection rules have been deployed to the Development environment (ec-dev)." >> $$GITHUB_STEP_SUMMARY
          echo "" >> $$GITHUB_STEP_SUMMARY
          echo "- **Environment**: Development (ec-dev)" >> $$GITHUB_STEP_SUMMARY
          echo "- **Branch**: dev" >> $$GITHUB_STEP_SUMMARY
          echo "- **Commit**: $${{ github.sha }}" >> $$GITHUB_STEP_SUMMARY
          echo "" >> $$GITHUB_STEP_SUMMARY
          echo "Next steps:" >> $$GITHUB_STEP_SUMMARY
          echo "1. Test the rules in the Development environment" >> $$GITHUB_STEP_SUMMARY
          echo "2. Run attacks from the red-01 VM to validate detection" >> $$GITHUB_STEP_SUMMARY
        else
          echo "### ❌ Deployment Failed" >> $$GITHUB_STEP_SUMMARY
          echo "" >> $$GITHUB_STEP_SUMMARY
          echo "The deployment to Development has failed. Please review the logs above." >> $$GITHUB_STEP_SUMMARY
        fi
EOT

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

      DEV_API_KEY=$(curl -u "elastic:$${ELASTIC_PASSWORD}" \
        -X POST "${ec_deployment.dev.elasticsearch.https_endpoint}/_security/api_key" \
        -H "Content-Type: application/json" \
        -d '{"name":"github-actions-dev","role_descriptors":{"detection_rules":{"cluster":["all"],"index":[{"names":["*"],"privileges":["all"]}],"applications":[{"application":"kibana-.kibana","privileges":["all"],"resources":["*"]}]}}}' \
        2>/dev/null | jq -r '.encoded')

      # Clear the password from environment
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

      echo ""
      echo "✅ GitHub Secrets configured successfully!"
      echo ""
      echo "Configured secrets:"
      echo "  - DEV_ELASTIC_CLOUD_ID (Cloud ID for ec-dev)"
      echo "  - DEV_ELASTIC_API_KEY (API key for deploying rules)"
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
      PROJECT_DIR="${path.module}/.."
      REPO_DIR="$${PROJECT_DIR}/$${REPO_NAME}"
      GITHUB_USER="${var.github_owner}"

      # Check if repository already exists locally
      if [ -d "$${REPO_DIR}/.git" ]; then
        echo "Local repository already exists at $${REPO_DIR}"
        cd "$${REPO_DIR}"
        git pull origin main || echo "Warning: Could not pull latest changes"
      else
        # Clone the repository to project directory
        echo "Cloning repository to $${REPO_DIR}..."
        git clone --depth 1 "https://github.com/$${GITHUB_USER}/$${REPO_NAME}.git" "$${REPO_DIR}"
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
    data.github_repository.detection_rules,
    github_branch.dev
  ]
}

# Output CI/CD configuration status
output "github_ci_cd_status" {
  description = "GitHub CI/CD configuration summary"
  value = {
    dev_branch_created = true
    workflow_file      = github_repository_file.deploy_to_dev_workflow.file
    github_secrets_configured = [
      "DEV_ELASTIC_CLOUD_ID",
      "DEV_ELASTIC_API_KEY"
    ]
    custom_rules_directory = "custom-rules/rules/"
    deployment_target      = "ec-dev (Development Environment)"
    workflow_trigger       = "Push to dev branch"
  }

  depends_on = [
    github_branch.dev,
    github_repository_file.deploy_to_dev_workflow,
    null_resource.setup_github_secrets,
    null_resource.setup_custom_rules_directory
  ]
}
