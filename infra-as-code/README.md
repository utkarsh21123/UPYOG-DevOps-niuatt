# infra-as-code

Infrastructure provisioning for the UPYOG platform using Terraform and Ansible.

## Structure

```
terraform/
├── egov-cicd/              # Active CI/CD infrastructure (EKS cluster + network + storage)
├── modules/                # Reusable Terraform modules
│   ├── Instance/aws-ec2/   # EC2 instance module
│   ├── db/                 # Database provisioning (AWS, Azure, GKE)
│   ├── kubernetes/         # K8s cluster modules (AWS EKS, Azure AKS, GKE)
│   ├── node-pool/aws/      # Node pool scaling
│   └── storage/            # Storage provisioning (AWS, Azure, GKE)
├── node-pool/              # Node pool configuration samples
├── sample-aws/             # Sample AWS deployment
├── sample-azure/           # Sample Azure deployment
├── sample-gke/             # Sample GKE deployment
├── sample-central-instance/# Central instance deployment
├── quickstart-aws-ec2/     # Quickstart single EC2 setup
└── scripts/                # Utility scripts (envYAML updater, dependency installers)

ansible/
├── Readme.md               # Kubespray documentation
└── haconfig.cfg            # HAProxy configuration for K8s API load balancing
```

## Key modules

- **kubernetes/aws/eks-cluster** — AWS EKS cluster definition with managed node groups
- **kubernetes/aws/network** — VPC, subnet, and gateway configuration
- **kubernetes/aws/workers** — Worker node group definitions (On-Demand and Spot)
- **storage/aws** — EBS CSI driver and storage class configuration
