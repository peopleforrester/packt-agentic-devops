# ABOUTME: One student EKS cluster, attached to the shared lab VPC. Instantiated once
# ABOUTME: per student by the fleet driver, each with its own state. The validated shape.
#
# Takes vpc_id and private_subnet_ids as inputs (no VPC of its own). Carries every fact
# the end-to-end validation resolved: 1x t3.2xlarge, VPC CNI prefix delegation plus
# maxPods=110, x86 AMI for the vLLM image, EBS CSI and the LB controller both on EKS Pod
# Identity (no IRSA/OIDC), and create_cloudwatch_log_group=false so reprovision is idempotent.

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
    tags = local.fleet_tags
  }
}

# One tag set, applied two ways: as provider default_tags (everything terraform creates) and
# as launch_template_tags (the node instance and its volumes, which default_tags cannot reach).
# The orphan sweep filters on Workshop=packt, so anything missing this tag is invisible to it.
locals {
  fleet_tags = {
    Workshop  = "packt"
    Project   = "packt-agentic-devops"
    Purpose   = "student-cluster"
    ManagedBy = "terraform"
    Student   = var.name
  }
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "profile" {
  type        = string
  description = <<-DESC
    AWS profile that owns this cluster. Deliberately has NO default: the fleet spans five
    accounts, and an implicit profile means a driver bug applies 50 clusters into whichever
    account the default names instead of failing. That is unrecoverable without a sweep.
  DESC
}

variable "name" {
  type        = string
  description = "Unique cluster name, one per student (e.g. student42)."
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
  # Pod Identity is the AWS-suggested default over IRSA; every workload here (EBS CSI, LB
  # controller) uses it, so no OIDC provider is created.
  enable_irsa = false

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
          # Tag the ENIs the CNI creates. Provider default_tags cannot reach them (the CNI, not
          # terraform, creates them), and an untagged ENI is invisible to the orphan sweep while
          # being exactly the thing that blocks a subnet delete with no useful error. Measured
          # before this: ~200 untagged network interfaces per 50-cluster account.
          ADDITIONAL_ENI_TAGS = jsonencode(local.fleet_tags)
        }
      })
    }
    kube-proxy = {
      before_compute = true
    }
    coredns                = {}
    eks-pod-identity-agent = {}
    aws-ebs-csi-driver = {
      # Pod Identity association wired into the addon so EKS creates it as part of the addon
      # lifecycle. Ordering-safe: no window where the controller starts without credentials.
      pod_identity_association = [{
        role_arn        = module.ebs_csi_pod_identity.iam_role_arn
        service_account = "ebs-csi-controller-sa"
      }]
    }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.2xlarge"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1

      # Root disk sized to measured need. The full platform pulls ~30 GB of container images
      # (the baked vLLM image dominates) and writes a few hundred MB to pod layers, for ~35 GB
      # used. 50 GB keeps imagefs at ~69%, below kubelet's 85% image-GC high threshold (so the
      # baked vLLM image is never collected mid-workshop) and well above the 10% eviction floor.
      #
      # disk_size is deliberately NOT set: this module manages a launch template for the node
      # group, and disk_size is SILENTLY IGNORED when a launch template exists. A bare
      # disk_size left the root volume at the AL2023 default of 20 GB, DiskPressure evicted the
      # platform, and terraform reported success throughout. Do not re-add disk_size.
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Managed node groups do NOT propagate provider default_tags to the EC2 instances or
      # their volumes: launch-template tag_specifications are data inside the template, not
      # resources the provider tags. On the validation run these were tagged by hand. At 250
      # that does not happen, and an untagged instance is invisible to the orphan sweep, which
      # filters on Workshop=packt.
      tag_specifications   = ["instance", "volume", "network-interface"]
      launch_template_tags = local.fleet_tags

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

# Pod Identity role + policy for the EBS CSI driver (AWS-suggested default over IRSA as of
# 2026-07; EBS CSI supports Pod Identity). Role and policy only: associations stays empty
# because the addon block above creates the association via pod_identity_association, which
# keeps EKS in charge of the ordering.
module "ebs_csi_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name                      = "${var.name}-ebs-csi"
  attach_aws_ebs_csi_policy = true

  associations = {}
}

# Pod Identity for the AWS Load Balancer Controller (build-spec: Pod Identity, not IRSA,
# so the fleet uses a reusable role + a per-cluster association instead of 300 OIDC trust
# policies). Without this the controller is Degraded and no ingress/LB reconciles. The
# Helm chart creates the aws-load-balancer-controller SA in kube-system; this binds it.
module "aws_lb_controller_pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "~> 1.0"

  name                            = "${var.name}-aws-lbc"
  attach_aws_lb_controller_policy = true

  associations = {
    main = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "aws-load-balancer-controller"
    }
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} --profile ${var.profile} --kubeconfig /tmp/${module.eks.cluster_name}.kubeconfig"
}
