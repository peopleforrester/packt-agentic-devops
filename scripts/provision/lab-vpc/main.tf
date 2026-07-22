# ABOUTME: The shared lab VPC, provisioned once. All student clusters attach to its
# ABOUTME: subnets, so the fleet shares one VPC and one NAT instead of one each.
#
# Sized for prefix delegation, which is the real constraint: each t3.2xlarge node with
# maxPods=110 consumes ~112 IPs (7x /28 prefixes), not 1. /18 private subnets (16,384 IPs
# each) hold ~60 concurrent single-node clusters with headroom. One shared NAT keeps cost
# flat instead of one NAT per cluster. This is a lab network, not production multi-tenancy:
# isolation between student clusters is in-cluster (NetworkPolicy), not at the VPC.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
  default_tags {
    tags = {
      Workshop  = "packt"
      Project   = "packt-agentic-devops"
      Purpose   = "lab-shared-vpc"
      ManagedBy = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "profile" {
  type        = string
  description = <<-DESC
    AWS profile that owns this lab VPC. No default on purpose: one VPC is applied per account
    across five accounts, and an implicit profile silently points a second account's apply at
    the first account's state.
  DESC
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "packt-lab-vpc"
  cidr = "10.0.0.0/16"

  azs = local.azs
  # /18 private subnets: room for prefix-delegated nodes across ~60 concurrent clusters.
  private_subnets = ["10.0.0.0/18", "10.0.64.0/18"]
  # Small public subnets just for the shared NAT and any public LBs.
  public_subnets = ["10.0.128.0/24", "10.0.129.0/24"]

  # One shared NAT for the whole lab fleet, not one per cluster.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Subnet discovery tags so every cluster's AWS Load Balancer Controller finds them.
  # Role tags are deliberately the ONLY discovery tags here: in a shared VPC the
  # controller discovers subnets by role, so all clusters use the same subnets. A
  # per-cluster kubernetes.io/cluster/<name> ownership tag is neither required (EKS
  # relaxed that) nor correct on a shared subnet, so it is intentionally absent.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "region" {
  value = var.region
}
