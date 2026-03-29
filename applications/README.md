# Applications

This directory contains application deployments and configurations for the homelab infrastructure.

## Structure

```
applications/
├── kubernetes/         # Kubernetes manifests and Helm charts
│   ├── argocd/        # GitOps management
│   ├── monitoring/    # Prometheus, Grafana, etc.
│   ├── ingress/       # NGINX, cert-manager
│   └── storage/       # CSI drivers, storage classes
├── docker-compose/    # Standalone container applications
│   ├── monitoring/    # Monitoring stack for non-K8s hosts
│   └── utilities/     # Development and utility tools
└── configs/          # Application configuration templates
    ├── nginx/        # NGINX configurations
    └── monitoring/   # Monitoring configurations
```

## Deployment Methods

### Kubernetes Applications
Deploy applications to your Talos Kubernetes cluster:

```bash
# Apply specific application
kubectl apply -k applications/kubernetes/monitoring/

# Apply all applications
find applications/kubernetes/ -name kustomization.yaml -execdir kubectl apply -k . \;
```

### Docker Compose Applications
For services running directly on Proxmox hosts or dedicated VMs:

```bash
# Deploy monitoring stack
docker-compose -f applications/docker-compose/monitoring/docker-compose.yml up -d

# Deploy utility services
docker-compose -f applications/docker-compose/utilities/docker-compose.yml up -d
```

## Application Categories

### Core Infrastructure
- **ArgoCD**: GitOps continuous delivery
- **cert-manager**: TLS certificate management
- **NGINX Ingress**: Load balancing and ingress

### Monitoring & Observability
- **Prometheus**: Metrics collection
- **Grafana**: Dashboards and visualization
- **AlertManager**: Alert routing and management
- **Loki**: Log aggregation

### Storage & Backup
- **Longhorn**: Distributed block storage for K8s
- **Velero**: Kubernetes backup and restore
- **MinIO**: S3-compatible object storage

### Development Tools
- **GitLab/Gitea**: Git repository management
- **Harbor**: Container registry
- **SonarQube**: Code quality analysis

## GitOps Integration

Applications are configured for GitOps deployment using ArgoCD:

1. **Application manifests** are stored in `kubernetes/` subdirectories
2. **ArgoCD applications** automatically sync from this repository
3. **Configuration changes** are applied via Git commits
4. **Rollbacks** are handled through ArgoCD UI or CLI

## Configuration Management

### Secrets
- Use **sealed-secrets** or **external-secrets** for K8s secrets
- Store sensitive configuration in **vars.yml** for Ansible-managed apps
- Never commit secrets to version control

### Environment-Specific Configuration
- Use **Kustomize** overlays for environment-specific configs
- Maintain **base** configurations in application directories
- Override values in environment-specific overlays

## Getting Started

1. **Deploy infrastructure** using Ansible playbooks
2. **Install ArgoCD** for GitOps management:
   ```bash
   kubectl apply -k applications/kubernetes/argocd/
   ```
3. **Configure ArgoCD** to watch this repository
4. **Deploy applications** through ArgoCD or kubectl

## Best Practices

- **Use Kustomize** for configuration management
- **Pin image tags** for reproducible deployments
- **Configure resource limits** for all workloads
- **Implement health checks** and readiness probes
- **Use service meshes** for advanced traffic management