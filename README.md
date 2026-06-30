# UPYOG DevOps

This repository contains the DevOps tooling and configuration for the **UPYOG** (formerly DIGIT/eGov) platform, covering the full infrastructure lifecycle — from provisioning cloud resources to deploying microservices on Kubernetes.

---

## Repository Structure

```
.
├── ci-as-code/           Jenkins CI/CD pipeline definitions (Groovy)
├── config-as-code/       Kubernetes Helm chart configurations (YAML)
├── deploy-as-code/       Go-based deployment tool (egov-deployer)
├── infra-as-code/        Infrastructure provisioning (Terraform + Ansible)
```

---

## ci-as-code/ — Jenkins CI/CD Pipelines

**Location:** `ci-as-code/`

Three Jenkins Pipeline Shared Library scripts that form a complete CI/CD lifecycle. All pipelines run inside Kubernetes pods as Jenkins agents (no agents running on the Jenkins master itself).

### Structure

```
ci-as-code/
├── src/org/egov/jenkins/        # Shared library source
│   ├── ConfigParser.groovy      # Parses build-config.yml into JobConfig + BuildConfig objects
│   ├── Utils.groovy             # Helper functions (folder path extraction, Git URL parsing)
│   └── models/
│       ├── BuildConfig.groovy   # Docker build definition model (context, imageName, dockerFile, workDir)
│       ├── JobConfig.groovy     # Jenkins job model (name + list of BuildConfigs)
│       └── CIConfig.java        # Placeholder (empty class)
└── vars/                        # Global pipeline variables (callable from any Jenkinsfile)
    ├── buildPipeline.groovy     # Docker image build & push pipeline
    ├── deployer.groovy          # Helm-based deployment pipeline
    └── jobBuilder.groovy        # Dynamic job generation via Job DSL
```

### How It Works

**The Three Pipelines:**

**1. `jobBuilder`** — Runs once when repos are added. Clones each microservice repo, reads its `build-config.yml`, and uses Jenkins Job DSL to dynamically create:
- Folder hierarchy in Jenkins (matching the repo structure)
- One `pipelineJob` per microservice (with Git branch parameter and log rotation)
- DockerHub repositories for each image

**2. `buildPipeline`** — Triggered per microservice commit. Runs inside a Kubernetes pod with a **Kaniko** container (for Docker builds without Docker-in-Docker) and a **git** container:
- Parses `build-config.yml` to determine build context and Dockerfile path
- Extracts application version and latest commit hash using shell scripts
- Builds the Docker image with Kaniko (with layer caching via PVC)
- Pushes to DockerHub — optionally also to GCR if `ALT_REPO_PUSH=true`
- Tags are formatted as `{imageName}:v{version}-{commit}-{buildNumber}`

**3. `deployer`** — Deploys built images. Runs inside a pod with the `egov-deployer` custom container:
- Mounts the target cluster's kubeconfig (Kubernetes secret)
- Executes `egov-deployer deploy` with Helm directory, environment name, and image list
- Handles namespace, ConfigMap, Secret, and service deployment

### Key Design

| Aspect | Choice |
|--------|--------|
| Docker build | **Kaniko** (no privileged containers, works on any K8s cluster) |
| Image caching | PVC-backed Kaniko cache for faster rebuilds |
| Job generation | **Jenkins Job DSL** — code-driven, no manual config |
| Config format | `build-config.yml` in each repo, shared across all three pipelines |
| Service categorization | Path-based regex (`core-services` → `CORE`, `municipal-services` → `MUNICIPAL`, etc.) |

---

## config-as-code/ — Helm Chart Configuration

**Location:** `config-as-code/`

All Kubernetes deployment configurations in Helm charts, organized by service category with environment-specific overrides and SOPS-encrypted secrets.

### Structure

```
config-as-code/
├── helm/
│   ├── environments/         # Environment-specific values
│   │   ├── {env}.yaml        #   Non-secret overrides (domains, image registry, replicas, ConfigMaps)
│   │   └── {env}-secrets.yaml #   SOPS-encrypted secrets (DB creds, API keys, payment gateway keys)
│   ├── charts/               # ~172 Helm charts
│   └── .sops.yaml            # SOPS encryption rules (AWS KMS)
├── product-release-charts/   # DIGIT version dependency manifests (v2.5–v2.7)
└── environments_old/          # Archived legacy configs
```

### How It Works

**Chart Categories (8 + 1 library):**

| Category | Count | What's Inside |
|----------|-------|---------------|
| `backbone-services/` | 38 | Infra: Kafka, Elasticsearch, Redis, PostgreSQL, Prometheus, Grafana, Cert-Manager, Ingress-Nginx, Minio, Jaeger, Jenkins |
| `core-services/` | 40 | Platform: egov-user, egov-mdms, egov-filestore, egov-workflow, egov-pdf, gateway, zuul, egov-location, egov-idgen, egov-searcher, egov-persister |
| `municipal-services/` | 46 | Modules: property-tax, trade-license, FSM, water/sewer, PGR, BPA, NOC, calculator services |
| `business-services/` | 18 | Finance: billing-service, collection-services, egf-* modules, egov-hrms, egov-apportion |
| `frontend/` | 18 | UI: citizen, employee, digit-ui, upyog-ui, hrms-web, workbench-ui |
| `utilities/` | 8 | Cron/data: data-upload, egov-custom-consumer, mailbot-cron, case-management |
| `dx-services/` | 2 | Digital experience: gis-dx-service, requester-services-dx |
| `cluster-configs/` | 1 | Cluster resources: namespaces, ConfigMaps, Secrets, RBAC, Ingress |
| `common/` | 1 | **Library chart** (used by all other charts) |

**The `common` Library Chart** — Every service chart depends on this. It provides 6 reusable templates:
- `common.deployment` — Full Deployment manifest with Flyway migrations, git-sync init containers, Java/Spring auto-config, Pod anti-affinity, health checks, rolling update
- `common.service` — Service with Prometheus scrape and Zuul routing annotations
- `common.ingress` — Ingress with WAF, TLS (cert-manager), regex path support, gateway routing
- `common.cronjob` — CronJob for scheduled tasks
- `common.servicemonitor` — Prometheus ServiceMonitor CRD
- `common.helpers` — Name/label/image template helpers

Service charts are minimal (1-2 lines per template), delegating entirely to the common library:
```yaml
{{- template "common.deployment" . -}}
```

**Environments** — Each environment has two override files under `helm/environments/`:
- `{env}.yaml` — Non-secret overrides: domain, image registry, replica counts, heap/memory, ConfigMap data (DB URLs, Kafka brokers, Elasticsearch hosts), service host mapping
- `{env}-secrets.yaml` — SOPS-encrypted secrets: DB credentials, SMS/Email provider keys, S3 keys, payment gateway credentials (Axis, PayU, Razorpay, CCAvenue), encryption keys

**SOPS Encryption** — Secrets are encrypted with [Mozilla SOPS](https://github.com/mozilla/sops) using AWS KMS. The `.sops.yaml` file defines path-based encryption rules — all secrets for a given environment use a single KMS key. At deploy time, the egov-deployer decrypts these automatically using the `sops -d` command.

**Environment variants:** `auat`, `ci`, `qa`, `qa2`, `qa-master`, `egov-demo` — with the `ci` environment focused on Jenkins/Cert-Manager, and others running the full UPYOG platform.

**`cluster-configs/` chart** is deployed first (before any services). It creates:
- Namespaces (`backbone`, `egov`, `cert-manager`, `monitoring`, etc.)
- Shared ConfigMaps (`egov-config` with DB/Kafka/ES URLs, `egov-service-host` with internal service discovery)
- Kubernetes Secrets (25+ types, sourced from encrypted env values)
- RBAC (ClusterRoles, RoleBindings)
- Root Ingress with TLS
- External DB Endpoint/Service (to point to RDS/Azure DB outside the cluster)

**Product Release Charts** — `product-release-charts/DIGIT/` contains dependency manifests for DIGIT releases v2.5, v2.6, v2.7. These define which microservice versions belong to each module, and the module dependency graph (e.g., `core` depends on `backbone` + `authn-authz`, `business` depends on `core`).

---

## deploy-as-code/ — Go-Based Deployment Tool

**Location:** `deploy-as-code/`

A standalone Go binary (`egov-deployer`) that deploys Helm charts onto Kubernetes clusters. It bundles kubectl, helm, and sops into a Docker image for a self-contained deployment runtime.

### Structure

```
deploy-as-code/deployer/
├── main.go                            # Entrypoint: calls cmd.Execute()
├── Dockerfile                         # Multi-stage build → alpine image with kubectl+helm+sops
├── digit_installer.go                 # Interactive DIGIT install wizard
├── full_installer.go                  # End-to-end installer (infra + deploy)
├── standalone_installer.go            # Standalone wizard (prompts for kubeconfig)
├── cmd/
│   ├── root.go                        # Cobra root command setup
│   └── deploy.go                      # `deployer deploy` subcommand
├── configs/
│   └── deployment_configurator.go     # Terraform output parsing, env config writing
└── pkg/cmd/deployer/
    ├── options.go                     # CLI options struct
    └── deployer.go                    # Core: DeployCharts(), helm/kubectl/sops execution
```

### How It Works

**CLI Usage:**
```bash
deployer deploy [flags] IMAGES
# Example:
deployer deploy -c -e qa egov-mdms-service,egov-user,egov-filestore
deployer deploy -c -e qa egov-mdms-service -p   # dry-run (prints rendered templates)
```

**Flags:**

| Flag | Purpose |
|------|---------|
| `--helm-dir` | Path to Helm charts (default: `../../config-as-code/helm`) |
| `-e` / `--environment` | **Required** — environment name (e.g., `qa`, `egov-demo`) |
| `-c` / `--cluster-configs` | Deploy cluster configs (namespaces, ConfigMaps, Secrets) before services |
| `-p` / `--print` | Dry-run mode — prints rendered YAML to stdout |

**Deployment Flow (`DeployCharts()`):**

1. **Build chart index** — Walks the Helm directory looking for `values.yaml` files, builds a service-name → chart-directory map

2. **Deploy cluster configs** (if `-c` flag) — Deploys the `cluster-configs` chart first:
   - Decrypts secrets via `sops -d` (if `.sops.yaml` exists)
   - Runs `helm template` → `kubectl apply` for namespaces, ConfigMaps, Secrets, RBAC

3. **Process each service image** — For each image in the comma-separated list:
   - Looks up the corresponding chart directory from the index
   - Resolves the image tag (uses provided tag, or queries the running cluster via `kubectl` for the current tag)
   - Runs `helm dep update` to resolve chart dependencies
   - Renders templates: `helm template --output-dir <tmpDir> -f <env>.yaml --set image.tag=<tag> .`
   - Applies manifests: `kubectl apply --recursive -f <tmpDir>`
   - CRDs are applied first via `kubectl apply -f crds/` if present

**Interactive Installers** (`digit_installer.go`, `full_installer.go`, `standalone_installer.go`) provide a wizard that:
- Lists available DIGIT product versions (v2.5–v2.7)
- Lets the user select modules interactively
- Resolves the module dependency graph (topological sort) so dependencies deploy before dependents
- Generates and executes the appropriate `deployer deploy` command

**Docker Image** — Multi-stage build (golang:1.13 → alpine:3) containing:
- `egov-deployer` binary
- kubectl v1.15.12 + aws-iam-authenticator (for EKS auth)
- sops v3.5.0 (for secret decryption)
- helm v3.2.1 (for chart templating)

---

## infra-as-code/ — Infrastructure Provisioning

**Location:** `infra-as-code/`

Terraform modules and Ansible configurations for provisioning cloud infrastructure — Kubernetes clusters, networking, databases, and storage — across AWS, Azure, and GCP.

### Structure

```
infra-as-code/
├── terraform/
│   ├── egov-cicd/           # Active CI/CD infrastructure
│   ├── modules/             # Reusable Terraform modules
│   │   ├── kubernetes/      # K8s cluster modules (EKS, AKS, GKE)
│   │   ├── storage/         # Persistent disk modules (EBS, Azure Disk, GCE PD)
│   │   ├── db/              # Database modules (RDS, Azure PG, Cloud SQL)
│   │   ├── Instance/        # EC2 key pair module
│   │   └── node-pool/       # EKS managed node group module
│   ├── sample-aws/          # Full production demo on AWS
│   ├── sample-azure/        # Full production demo on Azure
│   ├── sample-gke/          # Full production demo on GCP
│   ├── sample-central-instance/  # Multi-tenant EKS with per-module node groups
│   ├── node-pool/           # Standalone node group example
│   ├── quickstart-aws-ec2/  # Single EC2 quickstart
│   └── scripts/             # Utility scripts (Go, shell, Docker)
├── ansible/
│   ├── Readme.md            # Kubespray documentation
│   └── haconfig.cfg         # HAProxy config for K8s API load balancing
```

### How It Works

**Terraform Modules:**

| Module | Provider | What It Creates |
|--------|----------|-----------------|
| `kubernetes/aws/network` | AWS | VPC (192.168.0.0/16), public/private subnets per AZ, Internet Gateway, NAT Gateway + EIP, route tables, RDS security group |
| `kubernetes/aws/eks-cluster` | AWS | IAM Role + policies, EKS cluster (public endpoint), kubeconfig output |
| `kubernetes/aws/workers` | AWS | IAM Role + WorkerNode/CNI/ECR policies, Launch Template, AutoScaling Group with mixed instances (spot), bootstrap user-data |
| `kubernetes/azure` | Azure | Resource group, AKS cluster, default node pool, service principal |
| `kubernetes/gke` | GCP | VPC, GKE cluster (removes default pool), separate node pool with autoscaling |
| `storage/aws` | AWS | EBS volumes (configurable count, size, type, AZ, tags) |
| `storage/azure` | Azure | Azure managed disks |
| `storage/gke` | GCP | GCE persistent disks (pd-ssd) |
| `db/aws` | AWS | RDS PostgreSQL (subnet group, instance, configurable version/storage/backup) |
| `db/azure` | Azure | Azure PostgreSQL server + database |
| `db/gke` | GCP | Cloud SQL PostgreSQL + database (with maintenance window, binary logging) |
| `node-pool/aws` | AWS | EKS managed node group (IAM role, launch template, spot capacity, taints/labels, autoscaling) |
| `Instance/aws-ec2` | AWS | EC2 key pair |

**Active Infrastructure (`egov-cicd/`):**
The `egov-cicd/` directory provisions the Jenkins CI/CD environment itself:
```hcl
module.network → module.eks → module.jenkins (EBS volume)
```
- VPC (192.168.0.0/16) with public/private subnets and NAT
- EKS cluster (terraform-aws-modules/eks v21.24.0) with managed spot node group (t3.xlarge, 1 node) and CoreDNS/kube-proxy/vpc-cni addons
- 80GB gp3 EBS volume tagged `jenkins-home`

**Sample Deployments** (full production-grade platform):

- **sample-aws** — VPC + EKS + RDS (db.t3.medium, 10GB) + 9 EBS volumes (ES, Kafka, Zookeeper). State locking via S3 + DynamoDB.
- **sample-azure** — Resource Group + AKS (Standard_A8_v2, 4 nodes) + Azure PG + managed disks
- **sample-gke** — VPC + GKE (n1-standard-1, 2-4 nodes, autoscaling) + Cloud SQL + PD disks
- **sample-central-instance** — Multi-tenant EKS with **5 managed node groups** per module (digit, urban, sanitation, ifix, mgramseva), each with dedicated taints for workload isolation
- **quickstart-aws-ec2** — Single EC2 (c5.2xlarge) for quick evaluation

**Scripts:**

| Script | What It Does |
|--------|--------------|
| `init.go` | Reads `input.yaml`, validates names, replaces placeholders in `.tf` files and config-as-code YAML files |
| `envYAMLUpdater.go` | Reads `terraform output -json`, parses volume IDs, DB endpoints, and kubeconfig — writes to config-as-code environment files |
| `install_dependencies_mac.sh` | Installs kubectl, k9s, aws-iam-authenticator, AWS CLI, Terraform, Go, Helm via Homebrew |
| `install_dependencies_ubuntu.sh` | Same toolchain on Ubuntu via apt/curl |
| `Dockerfile` | CI/CD container image with kubectl, aws-cli v2, Go, Helm, Terraform 1.0.0 |

**Provisioning Workflow:**
```
network module ──► eks module ──► db module ──► storage modules
     │                │              │
     ▼                ▼              ▼
  VPC + Subnets   EKS Cluster    RDS/Cloud SQL     EBS/PD volumes
  + NAT/IGW       + Node Groups  + Database         (consumed by K8s PVCs)
```

Each module outputs its infrastructure IDs, which are consumed by dependent modules as inputs. The `envYAMLUpdater.go` script bridges Terraform outputs to Helm chart values, completing the infra-to-deploy pipeline.

**Ansible (Alternative Deployment Method):**
The `ansible/` directory contains an HAProxy configuration for a **Kubespray-deployed** Kubernetes cluster (on-prem/VM-based, as opposed to managed EKS/AKS/GKE). The `haconfig.cfg` provides:
- TCP load balancing for HTTP (port 80), HTTPS (port 443), and K8s API (port 6443)
- Round-robin across 4 worker nodes (HTTP/HTTPS via NodePort) and 3 master nodes (K8s API)
- IP whitelist for K8s API access (17 allowed IPs)
- `send-proxy` for client IP preservation
