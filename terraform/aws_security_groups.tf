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
