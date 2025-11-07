#!/bin/bash

################################################################################
# Elastic Security Demo - Vulnerable Tomcat Server Setup
# 
# Purpose: Automated setup of intentionally vulnerable Tomcat server for
#          security detection demonstration in isolated lab environment
#
# WARNING: This creates an INSECURE system with known vulnerabilities
#          ONLY run in isolated lab/demo environments
#          DO NOT use in production or internet-accessible systems
#
# Target OS: Ubuntu 20.04 or 22.04 LTS
# Tomcat Version: 9.0.30 (contains known vulnerabilities)
# 
# Author: Stuart, Elastic Security Sales Engineering
# Last Updated: November 2025
################################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -eq 0 ]; then 
        print_error "Do not run this script as root. Run as regular user with sudo privileges."
        exit 1
    fi
}

# Function to verify sudo access
check_sudo() {
    if ! sudo -n true 2>/dev/null; then
        print_error "This script requires sudo privileges. Please run with a user that has sudo access."
        exit 1
    fi
}

################################################################################
# MAIN INSTALLATION
################################################################################

echo "=========================================="
echo "Elastic Security Demo - Target VM Setup"
echo "Vulnerable Tomcat Server Installation"
echo "=========================================="
echo ""

print_warn "⚠️  WARNING: This installs an INTENTIONALLY VULNERABLE system"
print_warn "⚠️  Only use in isolated lab environments"
print_warn "⚠️  Do NOT expose to the internet"
echo ""

# Verify not running as root
check_root
check_sudo

# Confirmation prompt
read -p "Are you sure you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    print_info "Installation cancelled"
    exit 0
fi

echo ""
print_info "Starting installation..."
echo ""

################################################################################
# STEP 1: Update system and install dependencies
################################################################################

print_info "[1/8] Updating system packages..."
sudo apt update -qq
sudo apt upgrade -y -qq

print_info "[1/8] Installing Java 11..."
sudo apt install -y openjdk-11-jdk wget curl > /dev/null 2>&1

# Verify Java installation
if ! java -version > /dev/null 2>&1; then
    print_error "Java installation failed"
    exit 1
fi

print_info "✓ Java $(java -version 2>&1 | head -n 1 | cut -d'"' -f2) installed"

################################################################################
# STEP 2: Create tomcat user
################################################################################

print_info "[2/8] Creating tomcat user..."

if id "tomcat" &>/dev/null; then
    print_warn "User 'tomcat' already exists, skipping creation"
else
    sudo useradd -r -m -U -d /opt/tomcat -s /bin/false tomcat
    print_info "✓ Tomcat user created"
fi

################################################################################
# STEP 3: Download and install Tomcat 9.0.30
################################################################################

print_info "[3/8] Downloading Tomcat 9.0.30..."

TOMCAT_VERSION="9.0.30"
TOMCAT_ARCHIVE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/${TOMCAT_ARCHIVE}"

cd /tmp

# Download Tomcat
if [ -f "$TOMCAT_ARCHIVE" ]; then
    print_warn "Tomcat archive already exists, skipping download"
else
    wget -q "$TOMCAT_URL"
    if [ $? -ne 0 ]; then
        print_error "Failed to download Tomcat"
        exit 1
    fi
fi

print_info "✓ Tomcat downloaded"

################################################################################
# STEP 4: Extract and install Tomcat
################################################################################

print_info "[4/8] Installing Tomcat to /opt/tomcat..."

# Remove existing installation if present
if [ -d "/opt/tomcat" ]; then
    print_warn "Existing Tomcat installation found, backing up..."
    sudo mv /opt/tomcat /opt/tomcat.backup.$(date +%s)
fi

# Create directory
sudo mkdir -p /opt/tomcat

# Extract
sudo tar xzf "$TOMCAT_ARCHIVE" -C /opt/tomcat --strip-components=1

# Set ownership
sudo chown -R tomcat:tomcat /opt/tomcat/

# Make scripts executable
sudo chmod -R u+x /opt/tomcat/bin/

print_info "✓ Tomcat installed to /opt/tomcat"

################################################################################
# STEP 5: Configure weak credentials (INTENTIONALLY INSECURE)
################################################################################

print_info "[5/8] Configuring Tomcat users (WEAK CREDENTIALS FOR DEMO)..."

# Backup original file
sudo cp /opt/tomcat/conf/tomcat-users.xml /opt/tomcat/conf/tomcat-users.xml.backup

# Create tomcat-users.xml with weak credentials
sudo tee /opt/tomcat/conf/tomcat-users.xml > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users xmlns="http://tomcat.apache.org/xml"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
              version="1.0">
<!--
  DEMO ENVIRONMENT ONLY - INTENTIONALLY WEAK CREDENTIALS
  Username: tomcat
  Password: tomcat
-->
  <role rolename="manager-gui"/>
  <role rolename="manager-script"/>
  <role rolename="manager-jmx"/>
  <role rolename="manager-status"/>
  <role rolename="admin-gui"/>
  <role rolename="admin-script"/>
  <user username="tomcat" password="tomcat" roles="manager-gui,manager-script,manager-jmx,manager-status,admin-gui,admin-script"/>
</tomcat-users>
EOF

print_info "✓ Weak credentials configured (tomcat/tomcat)"

################################################################################
# STEP 6: Remove remote access restrictions (INTENTIONALLY INSECURE)
################################################################################

print_info "[6/8] Removing remote access restrictions (INSECURE FOR DEMO)..."

# Manager app
sudo tee /opt/tomcat/webapps/manager/META-INF/context.xml > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Context antiResourceLocking="false" privileged="true" >
<!--
  DEMO ENVIRONMENT ONLY - REMOTE ACCESS ENABLED
  Default configuration restricts access to localhost only
  This configuration allows access from any IP
-->
<!--
  <Valve className="org.apache.catalina.valves.RemoteAddrValve"
         allow="127\.\d+\.\d+\.\d+|::1|0:0:0:0:0:0:0:1" />
-->
  <Manager sessionAttributeValueClassNameFilter="java\.lang\.(?:Boolean|Integer|Long|Number|String)|org\.apache\.catalina\.filters\.CsrfPreventionFilter\$LruCache(?:\$1)?|java\.util\.(?:Linked)?HashMap"/>
</Context>
EOF

# Host Manager app (if exists)
if [ -f /opt/tomcat/webapps/host-manager/META-INF/context.xml ]; then
    sudo tee /opt/tomcat/webapps/host-manager/META-INF/context.xml > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Context antiResourceLocking="false" privileged="true" >
<!--
  <Valve className="org.apache.catalina.valves.RemoteAddrValve"
         allow="127\.\d+\.\d+\.\d+|::1|0:0:0:0:0:0:0:1" />
-->
  <Manager sessionAttributeValueClassNameFilter="java\.lang\.(?:Boolean|Integer|Long|Number|String)|org\.apache\.catalina\.filters\.CsrfPreventionFilter\$LruCache(?:\$1)?|java\.util\.(?:Linked)?HashMap"/>
</Context>
EOF
fi

print_info "✓ Remote access enabled for Manager applications"

################################################################################
# STEP 7: Create systemd service
################################################################################

print_info "[7/8] Creating systemd service..."

sudo tee /etc/systemd/system/tomcat.service > /dev/null << 'EOF'
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking

User=tomcat
Group=tomcat

Environment="JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64"
Environment="JAVA_OPTS=-Djava.security.egd=file:///dev/urandom -Djava.awt.headless=true"

Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

RestartSec=10
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

print_info "✓ Systemd service created"

################################################################################
# STEP 8: Configure firewall (if UFW is enabled)
################################################################################

print_info "[8/8] Configuring firewall..."

if sudo ufw status | grep -q "Status: active"; then
    print_info "UFW is active, opening port 8080..."
    sudo ufw allow 8080/tcp > /dev/null 2>&1
    print_info "✓ Port 8080 opened in firewall"
else
    print_warn "UFW is not active, skipping firewall configuration"
fi

################################################################################
# START TOMCAT
################################################################################

print_info "Starting Tomcat service..."

sudo systemctl enable tomcat > /dev/null 2>&1
sudo systemctl start tomcat

# Wait for Tomcat to start
sleep 5

# Check if Tomcat is running
if sudo systemctl is-active --quiet tomcat; then
    print_info "✓ Tomcat is running"
else
    print_error "Tomcat failed to start"
    print_info "Check logs with: sudo journalctl -u tomcat -n 50"
    exit 1
fi

################################################################################
# INSTALLATION COMPLETE
################################################################################

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""

# Get private IP
PRIVATE_IP=$(hostname -I | awk '{print $1}')

echo "Tomcat Configuration:"
echo "  Version: 9.0.30 (VULNERABLE)"
echo "  Location: /opt/tomcat"
echo "  User: tomcat"
echo "  Port: 8080"
echo ""
echo "Access URLs:"
echo "  Home: http://${PRIVATE_IP}:8080"
echo "  Manager: http://${PRIVATE_IP}:8080/manager/html"
echo ""
echo "Credentials (WEAK - FOR DEMO ONLY):"
echo "  Username: tomcat"
echo "  Password: tomcat"
echo ""
echo "Service Management:"
echo "  Status: sudo systemctl status tomcat"
echo "  Start: sudo systemctl start tomcat"
echo "  Stop: sudo systemctl stop tomcat"
echo "  Restart: sudo systemctl restart tomcat"
echo "  Logs: sudo journalctl -u tomcat -f"
echo ""

print_warn "⚠️  SECURITY WARNINGS:"
echo "  ❌ Weak credentials (tomcat/tomcat)"
echo "  ❌ Remote access enabled for Manager apps"
echo "  ❌ Vulnerable Tomcat version (9.0.30)"
echo "  ❌ DO NOT expose to the internet"
echo "  ✅ Suitable ONLY for isolated lab demonstrations"
echo ""

################################################################################
# VERIFICATION
################################################################################

print_info "Running verification checks..."
echo ""

# Test 1: Check if port 8080 is listening
if sudo netstat -tlnp 2>/dev/null | grep -q ":8080"; then
    echo "✓ Port 8080 is listening"
else
    print_warn "⚠ Port 8080 is not listening (may still be starting)"
fi

# Test 2: Check if Tomcat responds
if curl -s http://localhost:8080 > /dev/null 2>&1; then
    echo "✓ Tomcat responds on port 8080"
else
    print_warn "⚠ Tomcat is not responding yet (may still be starting)"
fi

# Test 3: Check Manager access
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u tomcat:tomcat http://localhost:8080/manager/text/list 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Manager application is accessible with weak credentials"
else
    print_warn "⚠ Manager application returned HTTP $HTTP_CODE"
fi

echo ""
print_info "Setup complete! Target VM is ready for demo."
echo ""
print_info "Next steps:"
echo "  1. Install Elastic Agent on this VM"
echo "  2. Configure detection rules on attacker VM"
echo "  3. Run connectivity test from attacker VM"
echo "  4. Execute demo attack chain"
echo ""

################################################################################
# SAVE CONFIGURATION TO FILE
################################################################################

CONFIG_FILE="$HOME/tomcat_demo_config.txt"

cat > "$CONFIG_FILE" << ENDCONFIG
Elastic Security Demo - Target VM Configuration
Generated: $(date)

Server Information:
  Hostname: $(hostname)
  Private IP: $PRIVATE_IP
  OS: $(lsb_release -d | cut -f2)
  
Tomcat Configuration:
  Version: 9.0.30
  Installation: /opt/tomcat
  Port: 8080
  Service: tomcat.service
  
Access Information:
  Home: http://${PRIVATE_IP}:8080
  Manager: http://${PRIVATE_IP}:8080/manager/html
  
Credentials:
  Username: tomcat
  Password: tomcat
  
Security Status:
  ⚠️  INTENTIONALLY VULNERABLE - DEMO ONLY
  ⚠️  DO NOT expose to the internet
  
Service Commands:
  sudo systemctl status tomcat
  sudo systemctl start tomcat
  sudo systemctl stop tomcat
  sudo systemctl restart tomcat
  sudo journalctl -u tomcat -f
ENDCONFIG

print_info "Configuration saved to: $CONFIG_FILE"

################################################################################
# END OF SCRIPT
################################################################################