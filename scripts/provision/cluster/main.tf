# ABOUTME: One student EKS cluster, attached to the shared lab VPC. Instantiated once
# ABOUTME: per student by the fleet driver, each with its own state. The validated shape.
#
# Takes vpc_id and private_subnet_ids as inputs (no VPC of its own). Carries every fact
# the end-to-end validation resolved: 1x t3.2xlarge, VPC CNI prefix delegation plus
# maxPods=110, x86 AMI for the vLLM image, EBS CSI via IRSA, Pod Identity for the LB
# controller, and create_cloudwatch_log_group=false so reprovision is idempotent.

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
      Purpose   = "student-cluster"
      ManagedBy = "terraform"
      Student   = var.name
    }
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "profile" {
  type    = string
  default = "accen-dev"
}

variable "name" {
  type        = string
  description = "Unique cluster name, one per student (e.g. packt-student-001)."
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "vpc_id" {
  type        = string
  description = "Shared lab VPC id (from the lab-vpc root)."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Shared lab private subnet ids (from the lab-vpc root)."
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  # EKS auto-creates the control-plane log group and it survives destroy; let EKS own it
  # so a reused name never collides with "already exists" on reprovision.
  create_cloudwatch_log_group = false

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  addons = {
    vpc-cni = {
      before_compute = true
      # Prefix delegation: raises t3.2xlarge from 58 to ~110 pods so the whole platform
      # fits one node. Pairs with the node group maxPods=110 below.
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = {
      before_compute = true
    }
    coredns                = {}
    eks-pod-identity-agent = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.2xlarge"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      disk_size      = 80
      # AL2023 nodeadm ignores prefix delegation when computing max-pods, so set it
      # explicitly to the prefix-delegation value for t3.2xlarge.
      cloudinit_pre_nodeadm = [{
        content_type = "application/node.eks.aws"
        content      = <<-EOT
          apiVersion: node.eks.aws/v1alpha1
          kind: NodeConfig
          spec:
            kubelet:
              config:
                maxPods: 110
        EOT
      }]
    }
  }
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name             = "${var.name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} --profile ${var.profile} --kubeconfig /tmp/${module.eks.cluster_name}.kubeconfig"
}
