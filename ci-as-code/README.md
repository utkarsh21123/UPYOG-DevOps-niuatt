# ci-as-code

Jenkins CI/CD pipeline definitions and shared library scripts for the UPYOG platform.

## Structure

```
src/org/egov/jenkins/      # Groovy shared library source
├── ConfigParser.groovy    # Pipeline configuration parser
├── Utils.groovy           # Shared utility functions
└── models/                # Pipeline model classes

vars/                      # Jenkins Pipeline Shared Library variables
├── buildPipeline.groovy   # Build pipeline definition
├── deployer.groovy        # Deployment pipeline
└── jobBuilder.groovy      # Job builder pipeline
```

## Pipelines

- **buildPipeline** — Builds microservice artifacts and publishes them to artifact repositories
- **deployer** — Deploys built artifacts to target Kubernetes environments via Helm
- **jobBuilder** — Generates and manages Jenkins job configurations
