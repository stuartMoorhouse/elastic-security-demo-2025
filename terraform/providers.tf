terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    ec = {
      source  = "elastic/ec"
      version = "~> 0.10"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

# AWS Provider - uses AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY from environment
provider "aws" {
  region = var.aws_region
}

# Elastic Cloud Provider - uses EC_API_KEY from environment
provider "ec" {}

# GitHub Provider - uses GITHUB_TOKEN from environment
provider "github" {}
