# RED TEAM TEST PLAN
## Purple Team Exercise: Tomcat Server Compromise Emulation

**Exercise ID:** PT-2025-011  
**Date:** November 10, 2025  
**Classification:** INTERNAL USE ONLY  
**Red Team Lead:** [Red Team Operator]  
**White Team Contact:** [Exercise Coordinator]

---

## 1. EXECUTIVE SUMMARY

This test plan outlines a controlled adversary emulation exercise targeting a vulnerable Apache Tomcat server to validate detection capabilities and incident response procedures. The Red Team will simulate a financially-motivated threat actor exploiting weak credentials to establish persistence and conduct credential harvesting.

## 2. SCOPE

**In Scope:**
- Target Host: `blue-01` (IP address provided by White Team)
- Services: Apache Tomcat 9.0.30 Manager Interface (TCP/8080)
- Attack Surface: Public-facing web application with default credentials

**Out of Scope:**
- Production systems and customer data
- Lateral movement beyond designated test host
- Denial of service or destructive actions
- Social engineering of production staff

## 3. OBJECTIVES

**Primary Goal:** Achieve root-level access and establish persistent backdoor
**Secondary Goals:**
- Validate detection coverage across MITRE ATT&CK kill chain
- Test Security Operations Center (SOC) alert triage procedures
- Evaluate case management workflow in Elastic Security 9.2
- Verify detections in Development Kibana environment (ec-dev)

**Success Criteria:**
- 100% of attack stages generate corresponding detection alerts in ec-dev
- Blue Team creates case within 15 minutes of initial compromise
- All activities documented with IOCs for replay workshop

## 4. THREAT ACTOR PROFILE

**Adversary Emulation:** Generic financially-motivated cybercriminal  
**Sophistication Level:** Intermediate (publicly available tools only)  
**TTPs Reference:** MITRE ATT&CK Framework v14

## 5. ATTACK SCENARIO

### Phase 1: Initial Access (T1190 - Exploit Public-Facing Application)
**Technique:** Exploit Tomcat Manager with weak credentials (tomcat/tomcat)  
**Tool:** Metasploit Framework (`exploit/multi/http/tomcat_mgr_upload`)  
**Expected Detection:** Custom rule "Tomcat Manager Web Shell Deployment"

### Phase 2: Execution (T1059 - Command and Scripting Interpreter)
**Technique:** Deploy Java-based web shell via WAR file upload
**Payload:** Meterpreter reverse TCP (red-01:4444)
**Expected Detection:** "Suspicious Java Child Process" (OOTB)

### Phase 3: Discovery (T1082, T1033 - System/User Discovery)
**Commands:** `whoami`, `id`, `uname -a`, `cat /etc/passwd`  
**Expected Detection:** "Linux System Information Discovery" (OOTB)

### Phase 4: Privilege Escalation (T1548 - Abuse Elevation Control)
**Technique:** Sudo privilege exploitation  
**Expected Detection:** "Sudo Command Execution" (OOTB)

### Phase 5: Persistence (T1053.003 - Cron Job)
**Technique:** Scheduled task for callback every 15 minutes  
**Tool:** Metasploit persistence module  
**Expected Detection:** "Persistence via Cron Job" (OOTB)

### Phase 6: Credential Access (T1003.008 - /etc/passwd and /etc/shadow)
**Technique:** Local credential dumping  
**Tool:** Metasploit `post/linux/gather/hashdump`  
**Expected Detection:** "Potential Credential Access via /etc/shadow" (OOTB)

### Phase 7: Defense Evasion (T1070.003 - Clear Command History)
**Technique:** History file manipulation  
**Commands:** `unset HISTFILE`, `history -c`  
**Expected Detection:** "Indicator Removal - Clear Command History" (OOTB)

### Phase 8: Collection (T1074.001 - Local Data Staging)
**Technique:** Stage sensitive files in hidden directory  
**Actions:** Create `/tmp/.staging/`, compress data  
**Expected Detection:** "Data Staging in Unusual Location" (OOTB)

## 6. RULES OF ENGAGEMENT

**Authorization:** Approved by IT Security Management and Legal
**Timeframe:** 40-45 minute exercise window
**Command & Control:** Red Team VM (red-01) via encrypted C2 channel
**Data Handling:** No real data exfiltration; simulated only
**Incident Response:** White Team monitors; Blue Team responds naturally
**Emergency Stop:** Contact White Team immediately if production impact suspected

**Guardrails:**
- No modification of system backups or security tools
- No password changes for service accounts (test accounts only)
- Immediate halt if unintended lateral movement detected

## 7. INDICATORS OF COMPROMISE (IOCs)

**Network:**
- Source Host: red-01 (Red Team VM)
- Destination Host: blue-01 (Target VM)
- Ports: 8080 (HTTP), 4444 (Reverse Shell), 4445 (Persistence)

**Files:**
- `/opt/tomcat/webapps/shell.war` (Web shell)
- `/tmp/.staging/` (Staging directory)
- `/tmp/data.tar.gz` (Compressed archive)

**Processes:**
- Parent: `java` (Tomcat)
- Children: `bash`, `sh` with `-c` or `-i` arguments

## 8. DELIVERABLES

- Timestamped activity log with MITRE technique mappings
- Screenshot evidence of each attack phase
- List of observed detection alerts with timestamps
- Recommendations for detection coverage gaps (if any)

## 9. COMMUNICATIONS

**Pre-Exercise Brief:** 10 minutes before start (White Team + Red Team only)  
**Real-Time Updates:** White Team Slack channel (emergency only)  
**Post-Exercise Debrief:** Within 2 hours of completion (all teams)

---

**Red Team Lead Signature:** ___________________________ **Date:** __________  
**White Team Approval:** ___________________________ **Date:** __________