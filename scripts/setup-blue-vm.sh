#!/bin/bash
set -e

# Log all output to file for debugging
exec > >(tee -a /var/log/elastic-demo-setup.log)
exec 2>&1

echo "=========================================="
echo "Elastic Security Demo - Blue Team VM Setup"
echo "Vulnerable Tomcat Server Installation"
echo "Starting: $(date)"
echo "=========================================="
echo ""
echo "WARNING: Installing INTENTIONALLY VULNERABLE system"
echo "Only for isolated lab/demo environments"
echo ""

# Set hostname
echo "[1/8] Setting hostname..."
hostnamectl set-hostname blue-01

# Update system
echo "[2/8] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

# Install Java 11
echo "[3/8] Installing Java 11..."
apt-get install -y -qq openjdk-11-jdk wget curl net-tools

# Create tomcat user with login shell and sudo access (INTENTIONALLY INSECURE)
echo "[4/8] Creating tomcat user with sudo privileges..."
if ! id "tomcat" &>/dev/null; then
  useradd -m -U -d /opt/tomcat -s /bin/bash tomcat
  echo "tomcat:tomcat" | chpasswd
  echo "tomcat ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tomcat
  chmod 440 /etc/sudoers.d/tomcat
fi

# Download and install Tomcat 9.0.30 (VULNERABLE VERSION)
echo "[5/8] Downloading Tomcat 9.0.30..."
TOMCAT_VERSION="9.0.30"
TOMCAT_ARCHIVE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/${TOMCAT_ARCHIVE}"

cd /tmp
wget -q "${TOMCAT_URL}"

# Extract and install
echo "[6/8] Installing Tomcat..."
mkdir -p /opt/tomcat
tar xzf "${TOMCAT_ARCHIVE}" -C /opt/tomcat --strip-components=1
chown -R tomcat:tomcat /opt/tomcat/
chmod -R u+x /opt/tomcat/bin/

# Configure WEAK credentials (INTENTIONALLY INSECURE)
echo "[7/8] Configuring weak credentials (tomcat/tomcat)..."
cat > /opt/tomcat/conf/tomcat-users.xml << 'TOMCATUSERS'
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users xmlns="http://tomcat.apache.org/xml"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
              version="1.0">
  <role rolename="manager-gui"/>
  <role rolename="manager-script"/>
  <role rolename="manager-jmx"/>
  <role rolename="manager-status"/>
  <role rolename="admin-gui"/>
  <role rolename="admin-script"/>
  <user username="tomcat" password="tomcat" roles="manager-gui,manager-script,manager-jmx,manager-status,admin-gui,admin-script"/>
</tomcat-users>
TOMCATUSERS

# Remove remote access restrictions (INTENTIONALLY INSECURE)
cat > /opt/tomcat/webapps/manager/META-INF/context.xml << 'MANAGERCTX'
<?xml version="1.0" encoding="UTF-8"?>
<Context antiResourceLocking="false" privileged="true" >
  <Manager sessionAttributeValueClassNameFilter="java\.lang\.(?:Boolean|Integer|Long|Number|String)|org\.apache\.catalina\.filters\.CsrfPreventionFilter\$LruCache(?:\$1)?|java\.util\.(?:Linked)?HashMap"/>
</Context>
MANAGERCTX

if [ -f /opt/tomcat/webapps/host-manager/META-INF/context.xml ]; then
  cat > /opt/tomcat/webapps/host-manager/META-INF/context.xml << 'HOSTCTX'
<?xml version="1.0" encoding="UTF-8"?>
<Context antiResourceLocking="false" privileged="true" >
  <Manager sessionAttributeValueClassNameFilter="java\.lang\.(?:Boolean|Integer|Long|Number|String)|org\.apache\.catalina\.filters\.CsrfPreventionFilter\$LruCache(?:\$1)?|java\.util\.(?:Linked)?HashMap"/>
</Context>
HOSTCTX
fi

# Create systemd service
echo "[8/8] Creating systemd service..."
cat > /etc/systemd/system/tomcat.service << 'TOMCATSVC'
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
TOMCATSVC

# Start Tomcat
systemctl daemon-reload
systemctl enable tomcat
systemctl start tomcat

# Wait for Tomcat to start
sleep 10

# Create sensitive files for the demo attack to collect
# These files will trigger the "Sensitive Files Compression" detection rule
echo "[8b/8] Creating sensitive files for demo..."

# IMPORTANT: Do NOT overwrite authorized_keys - just append a demo key
mkdir -p /home/ubuntu/.ssh
chmod 700 /home/ubuntu/.ssh
# Append demo key to existing authorized_keys (preserves real SSH access)
if ! grep -q "demo-key-for-detection" /home/ubuntu/.ssh/authorized_keys 2>/dev/null; then
    echo "# Demo authorized_keys entry for purple team exercise (attacker collection target)" >> /home/ubuntu/.ssh/authorized_keys
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... demo-key-for-detection" >> /home/ubuntu/.ssh/authorized_keys
fi
chmod 600 /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/.ssh

# Create a bash_history with some fake commands
cat > /home/ubuntu/.bash_history << 'HISTORY'
ls -la
cd /var/log
cat /etc/passwd
sudo apt update
systemctl status tomcat
HISTORY
chown ubuntu:ubuntu /home/ubuntu/.bash_history

# Get IP address
PRIVATE_IP=$(hostname -I | awk '{print $1}')

# Create configuration file
cat > /home/ubuntu/blue-vm-info.txt << ENDCONFIG
Elastic Security Demo - Blue Team VM Configuration
Generated: $(date)

Server Information:
  Hostname: $(hostname)
  Private IP: ${PRIVATE_IP}
  Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "N/A")

Tomcat Configuration:
  Version: 9.0.30 (VULNERABLE)
  Location: /opt/tomcat
  Port: 8080
  Service: tomcat.service

Access URLs:
  Home: http://${PRIVATE_IP}:8080
  Manager: http://${PRIVATE_IP}:8080/manager/html

Credentials (WEAK - FOR DEMO ONLY):
  Username: tomcat
  Password: tomcat
  Sudo Access: YES (password: tomcat)

Service Commands:
  sudo systemctl status tomcat
  sudo systemctl restart tomcat
  sudo journalctl -u tomcat -f

SECURITY WARNINGS:
  - Weak credentials (tomcat/tomcat)
  - tomcat user has sudo with password 'tomcat'
  - Remote access enabled
  - Vulnerable Tomcat version (9.0.30)
  - DO NOT expose to internet
  - For isolated lab use ONLY

Next Steps:
  1. Install Elastic Agent (see blue-vm.md)
  2. Configure agent to connect to ec-dev
  3. Verify connectivity from red-01
ENDCONFIG

chown ubuntu:ubuntu /home/ubuntu/blue-vm-info.txt

echo ""
echo "=========================================="
echo "Blue Team VM Setup Complete!"
echo "Completed: $(date)"
echo "=========================================="
echo ""
echo "Tomcat is running on port 8080"
echo "Setup log: /var/log/elastic-demo-setup.log"
echo "Configuration: /home/ubuntu/blue-vm-info.txt"
echo ""
echo "SECURITY WARNING: This is an intentionally vulnerable system"
echo "Do NOT expose to the internet!"
