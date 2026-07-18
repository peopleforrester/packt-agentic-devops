# ABOUTME: Terraform for an ephemeral EKS cluster shaped exactly like a student cluster
# ABOUTME: (1x t3.2xlarge) for the end-to-end validation. Provision, validate, destroy.

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
  # Every taggable resource gets Workshop=packt so it is unmistakable in the shared
  # account (another project, watchitburn, uses the same account). Filter or clean up by
  # this tag, never by guessing.
  default_tags {
    tags = {
      Workshop  = "packt"
      Project   = "packt-agentic-devops"
      Purpose   = "agentic-devops-validation"
      ManagedBy = "terraform"
      Ephemeral = "true"
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
  type    = string
  default = "adwc-dev"
}

variable "kubernetes_version" {
  type = string
  # EKS standard support (June 2026): 1.36, 1.35, 1.34. 1.33 exits July 29, 2026.
  default = "1.35"
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

  name = "${var.name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = local.azs
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # Lean: one NAT gateway shared across AZs, not one per AZ.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Tags the AWS Load Balancer Controller and EKS expect for subnet discovery.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  # Reachable from this workstation for bootstrap and validation. Ephemeral cluster.
  endpoint_public_access = true

  # nwuser (the Terraform principal) gets cluster admin via an access entry.
  enable_cluster_creator_admin_permissions = true

  # Pod Identity is the AWS-suggested default over IRSA; every workload here (EBS CSI, LB
  # controller) uses it, so no OIDC provider is created. Mirrors the fleet cluster module
  # so this throwaway validates the exact identity model students get (decision D16).
  enable_irsa = false

  # Do not let the module manage the control-plane CloudWatch log group. EKS auto-creates
  # /aws/eks/<name>/cluster, and it survives destroy, so a module-managed group collides
  # with "already exists" on any re-provision that reuses the cluster name. Letting EKS
  # own it makes provision idempotent across destroy/apply cycles.
  create_cloudwatch_log_group = false

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    # vpc-cni and kube-proxy must exist before nodes join. Without before_compute
    # the node group is created first, nodes boot with no CNI, stay NotReady, and
    # the group fails with NodeCreationFailure: Unhealthy nodes.
    # Prefix delegation is the reason the whole platform fits on one t3.2xlarge. The
    # default VPC CNI allocates one IP per ENI slot, capping t3.2xlarge at 58 pods; the
    # full platform (kagent alone runs ~8 agents) needs ~75 and the extras go Pending.
    # Prefix delegation assigns /28 prefixes, raising the ceiling to ~110. Set before
    # compute so the node calculates the higher max-pods at boot. Pairs with the node
    # group cloudinit maxPods below.
    vpc-cni = {
      before_compute = true
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
    # coredns runs on the nodes, so it installs after the node group exists.
    coredns = {}
    # Pod Identity agent, plus the EBS CSI driver on a Pod Identity association. EKS ships
    # no default StorageClass since 1.30; without this driver and the gp3 class,
    # observability PVCs (Prometheus, Loki) hang Pending.
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
    # One t3.2xlarge: the exact per-student shape (build-spec 6.6). Single node so the
    # validation mirrors what a student runs, never a roomier cluster (that is a false
    # pass). t3.2xlarge is the T3 ceiling and the only T3 size that fits CPU vLLM.
    # x86 AMI because the vLLM image is vllm-openai-cpu:*-x86_64. Larger root disk for
    # the vLLM image plus model weights and container layers.
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.2xlarge"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      disk_size      = 80
      # AL2023 nodeadm sets max-pods from a static per-instance map that ignores prefix
      # delegation, so raise it explicitly to the prefix-delegation value for t3.2xlarge
      # (110). Without this the node still caps at 58 even with prefix delegation on.
      # Verify the node reports ~110 allocatable pods on the next provision.
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

# Pod Identity for the AWS Load Balancer Controller (build-spec: Pod Identity, not IRSA).
# Without this the controller is Degraded and no ingress/LB reconciles. The Helm chart
# creates the aws-load-balancer-controller SA in kube-system; this binds it to a role
# carrying the LB controller policy.
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

# Tracking beyond the state file: a tag-based Resource Group so the AWS console lists
# every Workshop=packt resource live, independent of who ran Terraform. Clean up the
# whole footprint by filtering on this group / tag.
resource "aws_resourcegroups_group" "packt" {
  name = "packt-agentic-devops"
  # AWS allows only [\sa-zA-Z0-9_.-] here: no parentheses, no equals sign.
  description = "All resources for the Packt Agentic DevOps workshop. Tag Workshop is packt."
  resource_query {
    query = jsonencode({
      ResourceTypeFilters = ["AWS::AllSupported"]
      TagFilters          = [{ Key = "Workshop", Values = ["packt"] }]
    })
  }
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "resource_group" {
  value = aws_resourcegroups_group.packt.name
}

output "region" {
  value = var.region
}

output "update_kubeconfig" {
  value = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region} --profile ${var.profile}"
}
