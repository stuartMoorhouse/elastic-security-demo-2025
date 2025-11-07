# Project Configuration
variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "elastic-security-demo"
}

# AWS Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_instance_type" {
  description = "EC2 instance type (should have ~8GB RAM)"
  type        = string
  default     = "t3.large"
}

variable "aws_ami_owner" {
  description = "Owner ID for Ubuntu AMI"
  type        = string
  default     = "099720109477" # Canonical
}

variable "aws_ami_name_filter" {
  description = "Name filter for Ubuntu AMI"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH to VMs"
  type        = string
  default     = "0.0.0.0/0" # Restrict this to your IP for security
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Elastic Cloud Configuration
variable "ec_region" {
  description = "Elastic Cloud region"
  type        = string
  default     = "us-east-1"
}

variable "elastic_version" {
  description = "Elastic Stack version"
  type        = string
  default     = "9.2.0"
}

variable "deployment_template_id" {
  description = "Elastic Cloud deployment template"
  type        = string
  default     = "aws-io-optimized-v2"
}

variable "elasticsearch_size" {
  description = "Elasticsearch instance size (8GB RAM)"
  type        = string
  default     = "8g"
}

variable "elasticsearch_zone_count" {
  description = "Number of availability zones for Elasticsearch"
  type        = number
  default     = 1
}

variable "kibana_size" {
  description = "Kibana instance size"
  type        = string
  default     = "1g"
}

variable "kibana_zone_count" {
  description = "Number of availability zones for Kibana"
  type        = number
  default     = 1
}

variable "integrations_server_size" {
  description = "Integrations server instance size"
  type        = string
  default     = "1g"
}

variable "integrations_server_zone_count" {
  description = "Number of availability zones for Integrations server"
  type        = number
  default     = 1
}

# GitHub Configuration
variable "github_owner" {
  description = "GitHub username or organization"
  type        = string
}

variable "fork_name" {
  description = "Name for the forked detection-rules repository"
  type        = string
  default     = "detection-rules"
}
