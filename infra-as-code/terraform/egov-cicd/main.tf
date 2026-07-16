terraform {
  backend "s3" {
    bucket = "jenkins-statefile-niuattt"
    key = "terraform"
    region = "ap-south-1"
  }
}

module "network" {
  source             = "../modules/kubernetes/aws/network"
  vpc_cidr_block     = "${var.vpc_cidr_block}"
  cluster_name       = "${var.cluster_name}"
  availability_zones = "${var.network_availability_zones}"
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.0"
  name    = var.cluster_name
  vpc_id  = module.network.vpc_id
  kubernetes_version = var.kubernetes_version
  subnet_ids = concat(module.network.private_subnets, module.network.public_subnets)

  endpoint_public_access  = true
  endpoint_private_access = true
  authentication_mode     = "API"

  enable_cluster_creator_admin_permissions = true

  addons = {
    vpc-cni = {
      before_compute = true  # must be running before nodes join
    }
    coredns = {
      before_compute = false  # needs a node to schedule on
    }
    kube-proxy = {
      before_compute = false
    }
  }

  eks_managed_node_groups = {
    spot = {
      subnet_ids     = slice(module.network.private_subnets, 0, length(var.availability_zones))
      instance_types = var.override_instance_types

      min_size     = 1
      max_size      = var.number_of_worker_nodes
      desired_size  = var.number_of_worker_nodes

      capacity_type = "SPOT"

      # IMDSv2 hop limit of 2 required for containers to access instance metadata
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }

      labels = {
        "node.kubernetes.io/lifecycle" = "spot"
      }
    }
  }

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "KubernetesCluster"                         = var.cluster_name
  }
 
}

# Allow worker nodes to reach the EKS API server on port 443
resource "aws_security_group_rule" "nodes_to_cluster_api" {
  description              = "Worker nodes to cluster API server"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = module.eks.cluster_primary_security_group_id
  source_security_group_id = module.eks.node_security_group_id
}

#module "jenkins" {
#  source = "../modules/storage/aws"
#  storage_count = 1
#  environment = "${var.cluster_name}"
#  disk_prefix = "jenkins-home"
#  availability_zones = "${var.availability_zones}"
#  storage_sku = "gp3"
#  disk_size_gb = "50"
#}

# IRSA role for Jenkins deployer - allows KMS decryption of SOPS files
data "aws_iam_policy_document" "jenkins_irsa_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringLike"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:jenkins:*"]
    }
  }
}

data "aws_iam_policy_document" "jenkins_kms_decrypt" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*"
    ]
    resources = ["arn:aws:kms:ap-south-1:851725637287:key/4ac80ba0-2bb2-4e3e-9402-fc129402066a"]
  }
}

resource "aws_iam_role" "jenkins_irsa" {
  name               = "jenkins-niuatt-irsa"
  assume_role_policy = data.aws_iam_policy_document.jenkins_irsa_trust.json
}

resource "aws_iam_role_policy" "jenkins_kms_decrypt" {
  name   = "kms-decrypt-sops"
  role   = aws_iam_role.jenkins_irsa.id
  policy = data.aws_iam_policy_document.jenkins_kms_decrypt.json
}
