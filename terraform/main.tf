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

# Security Group for Attacker VM (red-01)
resource "aws_security_group" "attacker" {
  name        = "${var.project_name}-attacker-sg"
  description = "Security group for attacker VM (red-01)"
  vpc_id      = aws_vpc.main.id

  # SSH access from allowed CIDR
  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Metasploit listener port (from victim VM)
  ingress {
    description     = "Metasploit listener"
    from_port       = 4444
    to_port         = 4444
    protocol        = "tcp"
    security_groups = [aws_security_group.victim.id]
  }

  # Persistence callback port (from victim VM)
  ingress {
    description     = "Persistence callback"
    from_port       = 4445
    to_port         = 4445
    protocol        = "tcp"
    security_groups = [aws_security_group.victim.id]
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
    Name    = "${var.project_name}-attacker-sg"
    Project = var.project_name
    Role    = "attacker"
  }
}

# Security Group for Victim VM (blue-01)
resource "aws_security_group" "victim" {
  name        = "${var.project_name}-victim-sg"
  description = "Security group for victim VM (blue-01)"
  vpc_id      = aws_vpc.main.id

  # SSH access from allowed CIDR
  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # Tomcat port (from attacker VM)
  ingress {
    description     = "Tomcat HTTP"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.attacker.id]
  }

  # ICMP for ping tests (from attacker VM)
  ingress {
    description     = "ICMP from attacker"
    from_port       = -1
    to_port         = -1
    protocol        = "icmp"
    security_groups = [aws_security_group.attacker.id]
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
    Name    = "${var.project_name}-victim-sg"
    Project = var.project_name
    Role    = "victim"
  }
}

# SSH Key Pair
resource "aws_key_pair" "demo" {
  key_name   = "${var.project_name}-key"
  public_key = file("~/.ssh/id_rsa.pub")

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

# Attacker VM (red-01)
resource "aws_instance" "attacker" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.aws_instance_type
  key_name               = aws_key_pair.demo.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.attacker.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname red-01
              apt-get update
              EOF

  tags = {
    Name    = "red-01"
    Project = var.project_name
    Role    = "attacker"
  }
}

# Victim VM (blue-01)
resource "aws_instance" "victim" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.aws_instance_type
  key_name               = aws_key_pair.demo.key_name
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.victim.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname blue-01
              apt-get update
              EOF

  tags = {
    Name    = "blue-01"
    Project = var.project_name
    Role    = "victim"
  }
}
