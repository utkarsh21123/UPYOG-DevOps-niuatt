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

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  eks_managed_node_groups = {
    spot = {
      subnet_ids     = slice(module.network.private_subnets, 0, length(var.availability_zones))
      instance_types = var.override_instance_types

      min_size     = 1
      max_size     = var.number_of_worker_nodes
      desired_size = var.number_of_worker_nodes

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

module "jenkins" {

  source = "../modules/storage/aws"
  storage_count = 1
  environment = "${var.cluster_name}"
  disk_prefix = "jenkins-home"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp3"
  disk_size_gb = "80"
  
}
