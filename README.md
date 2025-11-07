# Elastic Security Demo 2025

A comprehensive demonstration environment showcasing Elastic Security 9.2 capabilities including Detection as Code (DaC), real-time threat detection, and case management.

## Overview

This project automates the deployment of a complete security demonstration environment featuring:

- **Detection as Code (DaC) workflow** - Version-controlled detection rules with GitOps
- **Red Team vs Blue Team simulation** - Live attack chain demonstration
- **Elastic Security 9.2 features** - Case management with auto-extracted observables
- **Full MITRE ATT&CK coverage** - Complete kill chain visibility

## Architecture

```
+------------------------------------------------------------------+
|                         AWS Environment                          |
+---------------------------+--------------------------------------+
|  Attacker VM (red-01)     |      Victim VM (blue-01)             |
|  - Ubuntu 22.04           |      - Ubuntu 22.04                  |
|  - Metasploit             |      - Vulnerable Tomcat 9.0.30      |
|  - detection-rules CLI    |      - Elastic Agent (dev)           |
|  - 8GB RAM (t3.large)     |      - 8GB RAM (t3.large)            |
+---------------------------+--------------------------------------+
                                    |
                                    v
+------------------------------------------------------------------+
|                    Elastic Cloud Deployments                     |
+---------------------------+--------------------------------------+
|  ec-local (8GB RAM)       |      ec-dev (8GB RAM)                |
|  - Rule development       |      - Demo target                   |
|  - Rule testing           |      - Attack detection              |
|  - Export rules           |      - Case management               |
+---------------------------+--------------------------------------+
                                    |
                                    v
+------------------------------------------------------------------+
|                      GitHub Repository                           |
|         Forked elastic/detection-rules                           |
|         - Custom detection rules                                 |
|         - Version control                                        |
|         - CI/CD (optional)                                       |
+------------------------------------------------------------------+
```

## Demo Workflow

1. **Design** - Create custom detection rule in Kibana (ec-local)
2. **Export** - Export rule to local detection-rules repository
3. **Commit** - Push rule to GitHub fork
4. **Deploy** - (Optional) CI/CD deploys to ec-dev
5. **Attack** - Execute attack chain from red-01 against blue-01
6. **Detect** - Rules trigger alerts in ec-dev
7. **Investigate** - Create case with auto-extracted observables
8. **Respond** - Document investigation and remediation

## Prerequisites

### Required Tools

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [GitHub CLI](https://cli.github.com/) (gh) authenticated
- SSH key pair at `~/.ssh/id_rsa` and `~/.ssh/id_rsa.pub`

### Required Accounts

- **AWS Account** - With permissions to create VPC, EC2, security groups
- **Elastic Cloud Account** - With API key for deployments
- **GitHub Account** - With repository creation permissions

### Required Environment Variables

Set these before running Terraform:

```bash
export AWS_ACCESS_KEY_ID="your-aws-access-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret-key"
export EC_API_KEY="your-elastic-cloud-api-key"
export GITHUB_TOKEN="your-github-token"
```

### Get Elastic Cloud API Key

1. Log in to [Elastic Cloud](https://cloud.elastic.co/)
2. Navigate to: Account > API Keys
3. Click "Create API Key"
4. Copy the key and set environment variable

### Authenticate GitHub CLI

```bash
# Authenticate with GitHub
gh auth login

# Verify authentication
gh auth status
```

## Quick Start

### 1. Clone and Configure

```bash
# Clone this repository
git clone <your-repo-url>
cd security-demo-2025

# Copy and edit terraform.tfvars
cd terraform
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

**Edit terraform.tfvars:**
- Change `YOUR_GITHUB_USERNAME` to your GitHub username
- Change `YOUR_IP/32` to your actual IP address (for SSH access)

### 2. Deploy Infrastructure

```bash
# From terraform/ directory
terraform init
terraform apply
```

**Deployment time:** ~8-10 minutes
- AWS resources: ~2 minutes
- Elastic Cloud deployments: ~5 minutes (may timeout but continues in background)
- GitHub fork: ~1 minute

**Important:** If Elastic Cloud deployments timeout after 2 minutes, this is expected behavior. Wait an additional 5 minutes, then run:

```bash
terraform refresh
terraform plan  # Verify everything is in state
```

### 3. View Outputs

```bash
# View all outputs
terraform output

# View specific passwords
terraform output elastic_local_password
terraform output elastic_dev_password

# Save outputs for reference
terraform output -json > ../deployment-info.json
```

### 4. Set Up VMs

Follow the detailed setup guides in the `instructions/` directory:

**Attacker VM (red-01):**
```bash
# SSH to attacker VM
ssh -i ~/.ssh/id_rsa ubuntu@<red-01-public-ip>

# Follow instructions/attacker-vm.md
# Installs: Metasploit, detection-rules, Python, nmap
```

**Victim VM (blue-01):**
```bash
# SSH to victim VM
ssh -i ~/.ssh/id_rsa ubuntu@<blue-01-public-ip>

# Follow instructions/victim-vm.md
# Installs: Vulnerable Tomcat 9.0.30, Elastic Agent
```

### 5. Run Demo

Follow `instructions/demo-execution-script.md` for the complete demonstration workflow.

## Project Structure

```
security-demo-2025/
├── README.md                    # This file
├── .gitignore                   # Git ignore rules
├── terraform/                   # Terraform configuration
│   ├── backend.tf              # State configuration
│   ├── providers.tf            # Provider definitions
│   ├── variables.tf            # Variable definitions
│   ├── main.tf                 # AWS resources
│   ├── elastic.tf              # Elastic Cloud deployments
│   ├── github.tf               # GitHub fork
│   ├── outputs.tf              # Output definitions
│   ├── terraform.tfvars        # Your values (gitignored)
│   └── terraform.tfvars.example # Example values
├── state/                       # Terraform state (gitignored)
├── instructions/                # Detailed setup guides
│   ├── prompt.md               # Original requirements
│   ├── attacker-vm.md          # Attacker VM setup
│   ├── victim-vm.md            # Victim VM setup
│   └── demo-execution-script.md # Demo workflow
└── example-terraform/           # Reference implementation
```

## Terraform State Management

This project uses local state stored in the `state/` directory (gitignored) to keep state separate from code.

**State location:** `state/terraform.tfstate`

**Important commands:**
```bash
# View current state
terraform show

# List resources in state
terraform state list

# Refresh state from cloud
terraform refresh

# Backup state before major changes
cp ../state/terraform.tfstate ../state/terraform.tfstate.backup
```

## Cost Estimates

Approximate monthly costs if running 24/7:

| Resource | Quantity | Monthly Cost |
|----------|----------|--------------|
| AWS EC2 t3.large | 2 | ~$120 |
| Elastic Cloud 8GB | 2 | ~$300 |
| AWS Networking | - | ~$5 |
| **Total** | | **~$425/month** |

**Cost savings tips:**
- Stop EC2 instances when not in use: `aws ec2 stop-instances --instance-ids i-xxx`
- Delete Elastic deployments after demo: Use Elastic Cloud console
- Run demo for testing only, then destroy: `terraform destroy`

## Demo Features

### Elastic Security 9.2 New Features

- **Human-readable Case IDs** - Case #0007 instead of UUIDs
- **Auto-extracted Observables** - Automatically extracts IPs, processes, files from alerts
- **Custom Observable Types** - Add custom indicators (CVEs, domains, etc.)
- **Enhanced Case Management** - Improved investigation workflow

### Attack Chain Coverage (MITRE ATT&CK)

- **Initial Access (T1190)** - Exploit Public-Facing Application (Tomcat)
- **Execution (T1059)** - Web shell deployment via Java
- **Discovery (T1082, T1033)** - System information gathering
- **Privilege Escalation (T1548)** - Sudo exploitation
- **Persistence (T1053.003)** - Cron job backdoor
- **Credential Access (T1003.008)** - /etc/shadow access
- **Defense Evasion (T1070.003)** - Command history clearing
- **Collection (T1074.001)** - Data staging

### Detection Rules

**Custom Rules:**
- Tomcat Manager Web Shell Deployment
- Suspicious Java Child Process Execution

**OOTB Rules Activated:**
- Linux System Information Discovery
- Persistence via Cron Job
- Potential Credential Access via /etc/shadow
- Suspicious Network Connection - Java Process
- Data Staging in Unusual Location
- Indicator Removal - Clear Command History

## Troubleshooting

### Elastic Cloud Timeout

**Problem:** Terraform times out after 2 minutes during `ec_deployment` creation

**Solution:** This is expected behavior. The deployment continues in the background.

```bash
# Wait 5 minutes, then:
terraform refresh
terraform plan  # Should show no changes
```

### SSH Connection Refused

**Problem:** Cannot SSH to EC2 instances

**Solutions:**
1. Wait 2-3 minutes for instances to fully boot
2. Verify security group allows your IP: `terraform apply` updates this
3. Check SSH key: `ssh-add ~/.ssh/id_rsa`

### GitHub Fork Fails

**Problem:** `gh repo fork` fails with authentication error

**Solutions:**
1. Re-authenticate: `gh auth login`
2. Verify token has repo permissions: `gh auth status`
3. Manual fork: Go to https://github.com/elastic/detection-rules and click "Fork"

### AWS Credentials Not Found

**Problem:** `Error: No valid credential sources`

**Solution:**
```bash
# Set environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"

# Or configure AWS CLI
aws configure
```

### Elastic Cloud API Key Invalid

**Problem:** `Error: Invalid API key`

**Solution:**
```bash
# Verify API key is set
echo $EC_API_KEY

# Create new API key in Elastic Cloud console
# Set environment variable
export EC_API_KEY="your-new-key"
```

## Cleanup

### Destroy Everything

```bash
cd terraform
terraform destroy
```

**Note:** GitHub fork is not automatically deleted. To delete manually:

```bash
gh repo delete <your-username>/detection-rules --yes
```

### Partial Cleanup

**Stop EC2 instances but keep Elastic:**
```bash
# Stop instances
aws ec2 stop-instances --instance-ids $(terraform output -json | jq -r '.attacker_vm.value.instance_id')
aws ec2 stop-instances --instance-ids $(terraform output -json | jq -r '.victim_vm.value.instance_id')

# Start them later
aws ec2 start-instances --instance-ids i-xxx i-yyy
```

**Delete Elastic deployments but keep AWS:**
```bash
# In terraform/elastic.tf, comment out the deployments
terraform apply -target=ec_deployment.local -target=ec_deployment.dev -destroy
```

## Support and Documentation

### Included Guides

- `instructions/attacker-vm.md` - Complete attacker VM setup (30-45 min)
- `instructions/victim-vm.md` - Vulnerable Tomcat installation script
- `instructions/demo-execution-script.md` - Full demo workflow (30-35 min)

### External Resources

- [Elastic Security Documentation](https://www.elastic.co/guide/en/security/current/)
- [Detection Rules Repository](https://github.com/elastic/detection-rules)
- [Metasploit Documentation](https://docs.metasploit.com/)
- [MITRE ATT&CK Framework](https://attack.mitre.org/)

### Reference Implementation

See `example-terraform/` directory for a more complex implementation with:
- CI/CD workflows
- Branch protection
- Automated deployments
- GitHub Actions integration

## Security Notes

**This is a demonstration environment with intentional vulnerabilities:**

- Vulnerable Tomcat version (9.0.30)
- Weak credentials (tomcat/tomcat)
- Publicly accessible manager interface
- No network segmentation

**Do NOT:**
- Use in production environments
- Expose to the public internet beyond demo duration
- Use real credentials or data
- Leave running unattended

**Do:**
- Restrict SSH access to your IP only
- Destroy infrastructure after demo
- Keep EC2 instances stopped when not in use
- Monitor AWS and Elastic Cloud costs
