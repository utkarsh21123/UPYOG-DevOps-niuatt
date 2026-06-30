# config-as-code

Kubernetes Helm chart configurations for the UPYOG platform. This directory contains all service definitions, environment-specific values, and dependency charts needed to deploy UPYOG onto Kubernetes clusters.

## Structure

```
helm/
├── environments/        # Environment-specific value files (auat, ci, qa, egov-demo)
│   ├── *.yaml           # Non-secret values per environment
│   └── *-secrets.yaml   # Encrypted (SOPS) secret values per environment
├── charts/              # Helm chart collections organized by service category
│   ├── backbone-services/    # 38 infra/backing services
│   ├── business-services/    # 18 business/financial modules
│   ├── cluster-configs/      # Cluster-level K8s resources
│   ├── common/               # Shared library chart
│   ├── core-services/        # 40 platform core services
│   ├── dx-services/          # 2 digital experience services
│   ├── frontend/             # 18 UI applications
│   ├── municipal-services/   # 46 municipal modules
│   ├── utilities/            # 8 utility/cron services
│   └── upyog-voice-bot/      # Voice bot service

environments_old/       # Legacy environment configs (archived)

product-release-charts/ # Product dependency charts for DIGIT releases (v2.5 - v2.7)
```

## Environment Configs

Each environment has a pair of YAML files under `helm/environments/`:
- `{env}.yaml` — non-sensitive values (image tags, replica counts, resource limits)
- `{env}-secrets.yaml` — encrypted secrets using Mozilla SOPS with AWS KMS
