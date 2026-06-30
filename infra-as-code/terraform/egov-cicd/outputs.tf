output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnets" {
  value = module.network.private_subnets
}

output "public_subnets" {
  value = module.network.public_subnets
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.cluster_endpoint
}

output "kubectl_config" {
  description = "Run this to configure kubectl after apply"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ap-south-1"
}


output "jenkins" {
  value = "${module.jenkins.volume_ids}"
}

