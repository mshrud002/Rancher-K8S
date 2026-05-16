# Rancher-K8S

[![CI](https://github.com/anomalyco/Rancher-K8S/actions/workflows/ci.yml/badge.svg)](https://github.com/anomalyco/Rancher-K8S/actions/workflows/ci.yml)

Deploy [Rancher](https://rancher.com) on **any** Kubernetes cluster — local (Kind, Minikube, K3s), OpenShift, baremetal, or cloud-managed (EKS, AKS, GKE).

## Quick Start

### Prerequisites

- `kubectl` connected to a K8s cluster
- `helm` (auto-installed if missing)

### Deploy

```bash
# Default: self-signed cert on any cluster (auto-detects distro)
./scripts/deploy-rancher.sh

# With Let's Encrypt on a real domain
./scripts/deploy-rancher.sh \
  --hostname rancher.example.com \
  --tls letsencrypt \
  --letsencrypt-email admin@example.com
```

### Get the bootstrap password

```bash
kubectl get secret --namespace cattle-system bootstrap-secret \
  -o jsonpath="{.data.bootstrapPassword}" | base64 -d
```

## Platform-Specific Deployment

### OpenShift

```bash
./scripts/deploy-openshift.sh
```

Auto-detects the OpenShift cluster domain, applies SCC permissions, deploys Rancher with an OpenShift Route instead of standard Ingress.

### Kind (local dev)

```bash
./scripts/deploy-kind.sh
```

Creates a Kind cluster with NGINX ingress, deploys Rancher, exposes on port 30443.

### Minikube (local dev)

```bash
./scripts/deploy-minikube.sh
```

Creates a Minikube cluster with ingress addon, starts tunnel, deploys Rancher.

### K3s (lightweight, local/production)

```bash
./scripts/deploy-k3s.sh
```

Installs K3s (if not present), deploys Rancher as single-node.

### Baremetal / Any Standard K8s

```bash
./scripts/deploy-rancher.sh --k8s-distro generic
```

The main script works on any standard Kubernetes distribution — baremetal K8s, kubeadm, RKE, RKE2, Talos, etc. It auto-detects the distro; `generic` is the fallback.

### Cloud: EKS / AKS / GKE

```bash
# Just point kubectl at your cloud cluster and run:
./scripts/deploy-rancher.sh \
  --hostname rancher.your-domain.com \
  --tls letsencrypt \
  --letsencrypt-email admin@example.com
```

### Bring Your Own Certificate

```bash
# Generate self-signed certs
./tls/generate-selfsigned-certs.sh rancher.example.com

# Or deploy with existing cert files
./scripts/deploy-rancher-ssl.sh rancher.example.com /path/to/tls.crt /path/to/tls.key
```

## Uninstall

```bash
# Remove Rancher only
./scripts/uninstall-rancher.sh

# Remove Rancher + cert-manager + all CRDs
./scripts/uninstall-rancher.sh --remove-cert-manager --remove-crds
```

## Project Structure

```
.
├── .github/workflows/
│   ├── ci.yml                  # ShellCheck, syntax check, kind integration test
│   └── release.yml             # Tag-based release artifacts
├── scripts/
│   ├── deploy-rancher.sh          # Universal deployer (works on any K8s)
│   ├── deploy-kind.sh             # Kind-specific setup
│   ├── deploy-minikube.sh         # Minikube-specific setup
│   ├── deploy-k3s.sh              # K3s-specific setup
│   ├── deploy-openshift.sh        # OpenShift-specific setup
│   ├── deploy-rancher-ssl.sh      # Deploy with custom TLS certs
│   └── uninstall-rancher.sh       # Cleanup
├── config/
│   └── rancher-values.yaml        # Helm values reference
├── tls/
│   └── generate-selfsigned-certs.sh
└── README.md
```

## Supported Platforms

| Platform    | Auto-detect | Ingress      | Notes                        |
|-------------|-------------|--------------|------------------------------|
| Kind        | yes         | NGINX        | Dev/test                     |
| Minikube    | yes         | NGINX        | Dev/test                     |
| K3s         | yes         | Traefik      | Lightweight / edge           |
| RKE2        | yes         | NGINX        | Production K8s               |
| OpenShift   | yes         | Route        | Uses SCC, `--disable-psp`   |
| EKS         | partial     | ALB / NGINX  | Cloud                        |
| AKS         | no          | AGIC / NGINX | Cloud                        |
| GKE         | yes         | GCLB / NGINX | Cloud                        |
| Generic     | fallback    | Any          | Baremetal, kubeadm, Talos... |

## Architecture

```
┌─────────────────────────────────────────────────┐
│                     User                         │
└──────────────────┬──────────────────────────────┘
                   │ HTTPS
                   ▼
┌──────────────────────────────────────────────────┐
│     Ingress / Route (nginx, traefik, ocp route)   │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│           Rancher Server (cattle-system)           │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  │
│  │  Rancher   │  │  Rancher   │  │  Rancher   │  │
│  │  Pod-1     │  │  Pod-2     │  │  Pod-3     │  │
│  └────────────┘  └────────────┘  └────────────┘  │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│             cert-manager                          │
│  (Issues/renews TLS certificates)                 │
└──────────────────────────────────────────────────┘
```
