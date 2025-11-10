# Data source to get latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = [var.aws_ami_owner]

  filter {
    name   = "name"
    values = [var.aws_ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-subnet"
    Project = var.project_name
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Security Group for Red Team VM (red-01)
resource "aws_security_group" "red" {
  name        = "${var.project_name}-red-sg"
  description = "Security group for red team VM (red-01)"
  vpc_id      = aws_vpc.main.id

  # SSH access from allowed CIDR
  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-red-sg"
    Project = var.project_name
    Role    = "red-team"
  }
}

# Security Group for Blue Team VM (blue-01)
resource "aws_security_group" "blue" {
  name        = "${var.project_name}-blue-sg"
  description = "Security group for blue team VM (blue-01)"
  vpc_id      = aws_vpc.main.id

  # SSH access from allowed CIDR
  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Tomcat HTTP access from allowed CIDR (for verification and demos)
  ingress {
    description = "Tomcat HTTP from allowed CIDR"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-blue-sg"
    Project = var.project_name
    Role    = "blue-team"
  }
}

# Security Group Rules for cross-references (to avoid circular dependency)

# Red team can receive connections from blue team on Metasploit ports
resource "aws_security_group_rule" "red_from_blue_4444" {
  type                     = "ingress"
  from_port                = 4444
  to_port                  = 4444
  protocol                 = "tcp"
  security_group_id        = aws_security_group.red.id
  source_security_group_id = aws_security_group.blue.id
  description              = "Metasploit listener from blue team"
}

resource "aws_security_group_rule" "red_from_blue_4445" {
  type                     = "ingress"
  from_port                = 4445
  to_port                  = 4445
  protocol                 = "tcp"
  security_group_id        = aws_security_group.red.id
  source_security_group_id = aws_security_group.blue.id
  description              = "Persistence callback from blue team"
}

# Blue team can receive connections from red team on Tomcat and ICMP
resource "aws_security_group_rule" "blue_from_red_8080" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.blue.id
  source_security_group_id = aws_security_group.red.id
  description              = "Tomcat HTTP from red team"
}

resource "aws_security_group_rule" "blue_from_red_icmp" {
  type                     = "ingress"
  from_port                = -1
  to_port                  = -1
  protocol                 = "icmp"
  security_group_id        = aws_security_group.blue.id
  source_security_group_id = aws_security_group.red.id
  description              = "ICMP from red team"
}

# SSH Key Pair
resource "aws_key_pair" "demo" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand("~/.ssh/id_ed25519.pub"))

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

# Red Team VM (red-01)
resource "aws_instance" "red" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.aws_instance_type
  key_name               = aws_key_pair.demo.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.red.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
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
              EOF

  tags = {
    Name    = "red-01"
    Project = var.project_name
    Role    = "red-team"
  }
}

# Blue Team VM (blue-01)
resource "aws_instance" "blue" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.aws_instance_type
  key_name               = aws_key_pair.demo.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.blue.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
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

              # Create tomcat user
              echo "[4/8] Creating tomcat user..."
              if ! id "tomcat" &>/dev/null; then
                useradd -r -m -U -d /opt/tomcat -s /bin/false tomcat
              fi

              # Download and install Tomcat 9.0.30 (VULNERABLE VERSION)
              echo "[5/8] Downloading Tomcat 9.0.30..."
              TOMCAT_VERSION="9.0.30"
              TOMCAT_ARCHIVE="apache-tomcat-$${TOMCAT_VERSION}.tar.gz"
              TOMCAT_URL="https://archive.apache.org/dist/tomcat/tomcat-9/v$${TOMCAT_VERSION}/bin/$${TOMCAT_ARCHIVE}"

              cd /tmp
              wget -q "$${TOMCAT_URL}"

              # Extract and install
              echo "[6/8] Installing Tomcat..."
              mkdir -p /opt/tomcat
              tar xzf "$${TOMCAT_ARCHIVE}" -C /opt/tomcat --strip-components=1
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

              # Get IP address
              PRIVATE_IP=$(hostname -I | awk '{print $1}')

              # Create configuration file
              cat > /home/ubuntu/blue-vm-info.txt << ENDCONFIG
              Elastic Security Demo - Blue Team VM Configuration
              Generated: $(date)

              Server Information:
                Hostname: $(hostname)
                Private IP: $${PRIVATE_IP}
                Public IP: $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "N/A")

              Tomcat Configuration:
                Version: 9.0.30 (VULNERABLE)
                Location: /opt/tomcat
                Port: 8080
                Service: tomcat.service

              Access URLs:
                Home: http://$${PRIVATE_IP}:8080
                Manager: http://$${PRIVATE_IP}:8080/manager/html

              Credentials (WEAK - FOR DEMO ONLY):
                Username: tomcat
                Password: tomcat

              Service Commands:
                sudo systemctl status tomcat
                sudo systemctl restart tomcat
                sudo journalctl -u tomcat -f

              SECURITY WARNINGS:
                - Weak credentials (tomcat/tomcat)
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

              # Verification
              echo ""
              echo "Verification:"
              if systemctl is-active --quiet tomcat; then
                echo "✓ Tomcat is running"
              else
                echo "✗ Tomcat failed to start"
              fi

              if netstat -tlnp 2>/dev/null | grep -q ":8080"; then
                echo "✓ Port 8080 is listening"
              else
                echo "✗ Port 8080 is not listening"
              fi

              if curl -s http://localhost:8080 > /dev/null 2>&1; then
                echo "✓ Tomcat responds on port 8080"
              else
                echo "✗ Tomcat is not responding"
              fi

              HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" -u tomcat:tomcat http://localhost:8080/manager/text/list 2>/dev/null || echo "000")
              if [ "$${HTTP_CODE}" = "200" ]; then
                echo "✓ Manager application accessible"
              else
                echo "✗ Manager returned HTTP $${HTTP_CODE}"
              fi

              echo ""
              echo "=========================================="
              echo "Blue Team VM Setup Complete!"
              echo "Completed: $(date)"
              echo "=========================================="
              echo ""
              echo "Setup log: /var/log/elastic-demo-setup.log"
              echo "Configuration: /home/ubuntu/blue-vm-info.txt"
              echo ""
              echo "Access Tomcat Manager: http://$${PRIVATE_IP}:8080/manager/html"
              echo "Credentials: tomcat/tomcat"
              EOF

  tags = {
    Name    = "blue-01"
    Project = var.project_name
    Role    = "blue-team"
  }
}
