# Local Machine Setup - Detection Rules CLI

## Overview

This guide will help you set up the detection-rules CLI on your local machine for rule development, export, and version control. All detection rule development happens on your local machine, NOT on the AWS VMs.

**Estimated Setup Time:** 20-30 minutes
**Requirements:** macOS, Linux, or Windows with WSL

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Clone Your Detection Rules Fork](#clone-your-detection-rules-fork)
3. [Set Up Python Environment](#set-up-python-environment)
4. [Install Detection Rules Package](#install-detection-rules-package)
5. [Configure Elastic Cloud Connections](#configure-elastic-cloud-connections)
6. [Verify Setup](#verify-setup)
7. [Development Workflow](#development-workflow)
8. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software

```bash
# Check Python version (3.12 recommended)
python3 --version

# Check git
git --version

# Check pip
pip3 --version
```

### Install Prerequisites

**macOS:**
```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Python 3.12
brew install python@3.12

# Verify
python3.12 --version
```

**Linux (Ubuntu/Debian):**
```bash
# Update package list
sudo apt update

# Install Python 3.12 and dependencies
sudo apt install -y python3.12 python3.12-venv python3-pip git

# Verify
python3.12 --version
```

**Windows (WSL2):**
```bash
# Inside WSL2 Ubuntu
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3-pip git
```

---

## Clone Your Detection Rules Fork

After Terraform deployment, get your fork URL:

```bash
# From terraform/ directory
cd terraform
terraform output github_repository

# Clone your fork
cd ~  # or your preferred projects directory
git clone <your-fork-url>
cd detection-rules

# Verify you're on the main branch
git branch
```

---

## Set Up Python Environment

Create a Python virtual environment for the detection-rules package:

```bash
# Make sure you're in the detection-rules directory
cd ~/detection-rules  # Adjust path if needed

# Create virtual environment with Python 3.12
python3.12 -m venv .venv

# Activate virtual environment
# macOS/Linux:
source .venv/bin/activate

# Windows (WSL2):
source .venv/bin/activate

# Your prompt should now show (.venv)
```

---

## Install Detection Rules Package

With the virtual environment activated:

```bash
# Upgrade pip
pip install --upgrade pip

# Install detection-rules package in editable mode
pip install -e ".[dev]"

# Install required libraries
pip install lib/kql
pip install lib/kibana

# Verify installation
python -m detection_rules --help
```

You should see the detection_rules CLI help output.

---

## Configure Elastic Cloud Connections

Get your Elastic Cloud credentials from Terraform:

```bash
# From terraform/ directory (in a new terminal, don't deactivate venv)
cd terraform

# Get ec-local credentials
terraform output elastic_local
terraform output elastic_local_password

# Get ec-dev credentials
terraform output elastic_dev
terraform output elastic_dev_password
```

### Create Configuration File

Back in your detection-rules directory with venv activated:

```bash
# Create config file
cat > .detection-rules-cfg.json << 'EOF'
{
  "custom_rules_dir": "dac-demo"
}
EOF

# For connecting to ec-local (rule development):
# You'll set these as environment variables when needed
```

### Set Environment Variables

Create a helper script for easy connection switching:

```bash
# Create connection helper scripts
cat > connect-local.sh << 'EOF'
#!/bin/bash
# Connect to ec-local for rule development

export ELASTIC_CLOUD_ID="<ec-local-cloud-id>"
export ELASTIC_API_KEY="<ec-local-api-key>"  # You'll create this

echo "Connected to ec-local"
echo "Cloud ID: $ELASTIC_CLOUD_ID"
EOF

cat > connect-dev.sh << 'EOF'
#!/bin/bash
# Connect to ec-dev (usually not needed, CI/CD handles this)

export ELASTIC_CLOUD_ID="<ec-dev-cloud-id>"
export ELASTIC_API_KEY="<ec-dev-api-key>"

echo "Connected to ec-dev"
echo "Cloud ID: $ELASTIC_CLOUD_ID"
EOF

chmod +x connect-local.sh connect-dev.sh

echo "Edit connect-local.sh and connect-dev.sh with your Elastic Cloud credentials"
```

### Create API Keys in Elastic Cloud

You need to create API keys for the detection-rules CLI:

1. **Log in to ec-local Kibana** (get URL from `terraform output elastic_local`)
2. **Navigate to:** Stack Management → Security → API Keys
3. **Click "Create API key"**
4. **Configure:**
   - Name: `detection-rules-cli`
   - Restrict privileges: No (full access needed for rule management)
5. **Copy the encoded API key** and save it in `connect-local.sh`

Repeat for ec-dev if needed (though CI/CD handles dev deployment).

---

## Verify Setup

Run these checks to ensure everything is working:

```bash
# Activate venv if not already active
source .venv/bin/activate

# Check detection_rules CLI
python -m detection_rules --version

# Load ec-local connection
source connect-local.sh

# Test connection to Kibana
python -m detection_rules kibana --space default list-rules

# You should see the list of installed detection rules
```

---

## Development Workflow

### 1. Create Detection Rule in Kibana

1. Log in to **ec-local** Kibana (rule development environment)
2. Navigate to: **Security → Rules → Detection rules (SIEM)**
3. Click **"Create new rule"**
4. Design your custom rule
5. Save and enable the rule

### 2. Export Rule from Kibana

```bash
# Activate venv
source .venv/bin/activate

# Connect to ec-local
source connect-local.sh

# Export specific rule by ID
python -m detection_rules kibana --space default export-rules \
  --rule-id <rule-id> \
  -o dac-demo/rules/

# Or export all rules to see what's available
python -m detection_rules kibana --space default export-rules \
  -o exported-rules/
```

### 3. Edit Rule File

```bash
# Rule is now in dac-demo/rules/your-rule.toml
# Edit as needed
nano dac-demo/rules/your-rule.toml

# Or use your preferred editor
code dac-demo/rules/your-rule.toml
```

### 4. Validate Rule Locally

```bash
# Validate syntax
python -m detection_rules test dac-demo/rules/your-rule.toml

# View rule details
python -m detection_rules view-rule dac-demo/rules/your-rule.toml
```

### 5. Commit and Push to GitHub

```bash
# Add the rule file
git add dac-demo/rules/your-rule.toml

# Commit with descriptive message
git commit -m "feat: Add Tomcat web shell detection rule

- Detects Java spawning shell interpreters
- Covers MITRE T1190 and T1505.003
- High severity, production ready"

# Push to dev branch (triggers CI/CD deployment to ec-dev)
git checkout dev
git merge main
git push origin dev

# GitHub Actions will automatically deploy to ec-dev
```

### 6. Verify Deployment

After pushing to dev branch:

1. Check GitHub Actions workflow run
2. Log in to **ec-dev** Kibana
3. Navigate to: **Security → Rules**
4. Verify your custom rule is deployed and enabled

---

## Troubleshooting

### Python Version Issues

```bash
# If you don't have Python 3.12
# Use pyenv to manage Python versions

# Install pyenv (macOS)
brew install pyenv

# Install Python 3.12
pyenv install 3.12.0
pyenv local 3.12.0

# Recreate venv
python -m venv .venv
source .venv/bin/activate
```

### Package Installation Errors

```bash
# If lib/kql or lib/kibana fail to install
cd lib/kql
pip install -e .
cd ../kibana
pip install -e .
cd ../..

# Retry main installation
pip install -e ".[dev]"
```

### API Connection Errors

```bash
# Verify your API key is correct
echo $ELASTIC_API_KEY

# Test connection with curl
curl -H "Authorization: ApiKey $ELASTIC_API_KEY" \
  "https://<kibana-url>/api/status"

# If API key expired, create a new one in Kibana
```

### Git Push Authentication Issues

```bash
# If pushing to GitHub fails
gh auth login

# Or set up SSH keys
ssh-keygen -t ed25519 -C "your_email@example.com"
cat ~/.ssh/id_ed25519.pub  # Add to GitHub

# Use SSH URL for git remote
git remote set-url origin git@github.com:<your-username>/detection-rules.git
```

---

## Quick Reference

### Essential Commands

```bash
# Activate environment
cd ~/detection-rules
source .venv/bin/activate
source connect-local.sh

# List rules in Kibana
python -m detection_rules kibana --space default list-rules

# Export specific rule
python -m detection_rules kibana --space default export-rules \
  --rule-id <rule-id> -o dac-demo/rules/

# Validate rule
python -m detection_rules test dac-demo/rules/your-rule.toml

# Import rule to Kibana
python -m detection_rules kibana --space default import-rules \
  -d dac-demo/rules/

# View rule details
python -m detection_rules view-rule dac-demo/rules/your-rule.toml
```

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/new-detection-rule

# Make changes, test locally
git add dac-demo/rules/
git commit -m "feat: Add new detection rule"

# Push to feature branch
git push origin feature/new-detection-rule

# Merge to dev for deployment
git checkout dev
git merge feature/new-detection-rule
git push origin dev  # Triggers CI/CD to ec-dev
```

---

## Directory Structure

After setup, your local machine should have:

```
~/detection-rules/
├── .venv/                   # Python virtual environment
├── .detection-rules-cfg.json # Configuration file
├── connect-local.sh         # Helper script for ec-local
├── connect-dev.sh           # Helper script for ec-dev
├── dac-demo/               # Custom rules directory
│   ├── rules/              # Your custom .toml rule files
│   ├── docs/               # Rule documentation
│   └── README.md           # Usage instructions
├── rules/                  # Elastic's OOTB rules (don't modify)
└── [other detection-rules repo files]
```

---

## Next Steps

1. **Set up red team VM** - Follow `instructions/red-vm.md`
2. **Set up blue team VM** - Follow `instructions/blue-vm.md`
3. **Create your first rule** - Use Kibana in ec-local
4. **Export and commit** - Use this workflow
5. **Run purple team exercise** - Follow `instructions/demo-execution-script.md`

---

## Resources

- **Detection Rules Repository:** https://github.com/elastic/detection-rules
- **Elastic Security Documentation:** https://www.elastic.co/guide/en/security/current/
- **Detection Rules Developer Guide:** https://github.com/elastic/detection-rules/blob/main/CONTRIBUTING.md
- **EQL Syntax Reference:** https://www.elastic.co/guide/en/elasticsearch/reference/current/eql-syntax.html

---

## Important Notes

- **All rule development happens locally** - Never install detection-rules CLI on AWS VMs
- **ec-local is for development** - Create and test rules here
- **ec-dev is for demonstration** - CI/CD deploys here from dev branch
- **GitHub is your source of truth** - All rules should be version controlled
- **Keep API keys secure** - Never commit them to git
