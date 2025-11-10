#!/bin/bash
set -e

# Log all output to file for debugging
exec > >(tee -a /var/log/elastic-demo-setup.log)
exec 2>&1

echo "=========================================="
echo "Elastic Security Demo - Red Team VM Setup"
echo "Starting: $(date)"
echo "=========================================="

# Set hostname
echo "[1/6] Setting hostname..."
hostnamectl set-hostname red-01

# Update system
echo "[2/6] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# Install dependencies
echo "[3/6] Installing dependencies..."
apt-get install -y -qq curl wget git build-essential libssl-dev \
  libreadline-dev zlib1g-dev nmap netcat-traditional postgresql \
  postgresql-contrib

# Install Metasploit Framework
echo "[4/6] Installing Metasploit Framework..."
cd /tmp
curl -s https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall
chmod 755 msfinstall
./msfinstall

# Initialize Metasploit database (must run as ubuntu user)
echo "[5/6] Initializing Metasploit database..."
su - ubuntu -c "msfdb init" || echo "Note: Database initialization skipped (run 'msfdb init' manually after login)"

# Install additional tools
echo "[6/6] Installing additional tools..."
apt-get install -y -qq john nikto

# Verify installation
echo ""
echo "Verification:"
msfconsole --version
nmap --version | head -1

# Create demo configuration file
cat > /home/ubuntu/red-vm-info.txt << 'ENDCONFIG'
Elastic Security Demo - Red Team VM Configuration
Generated: $(date)

Server Information:
  Hostname: $(hostname)
  Private IP: $(hostname -I | awk '{print $1}')
  Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "N/A")

Installed Tools:
  - Metasploit Framework (msfconsole)
  - Nmap (network scanning)
  - Netcat (network utilities)
  - John the Ripper (password cracking)
  - Nikto (web vulnerability scanning)

Quick Start:
  - Launch Metasploit: msfconsole
  - Check database: msfdb status
  - View logs: tail -f /var/log/elastic-demo-setup.log

Next Steps:
  1. Review demo-execution-script.md
  2. Configure target IP for blue-01
  3. Run attack scenarios
ENDCONFIG

chown ubuntu:ubuntu /home/ubuntu/red-vm-info.txt

echo ""
echo "=========================================="
echo "Red Team VM Setup Complete!"
echo "Completed: $(date)"
echo "=========================================="
echo ""
echo "Setup log: /var/log/elastic-demo-setup.log"
echo "Configuration: /home/ubuntu/red-vm-info.txt"
