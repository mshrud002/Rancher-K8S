#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-rancher-demo}"
K8S_VERSION="${K8S_VERSION:-v1.31.0}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.local}"
RANCHER_VERSION="${RANCHER_VERSION:-2.10.3}"
TLS_SOURCE="${TLS_SOURCE:-selfsigned}"
HTTP_NODE_PORT="${HTTP_NODE_PORT:-30080}"
HTTPS_NODE_PORT="${HTTPS_NODE_PORT:-30443}"
BOOTSTRAP_PASSWORD="${BOOTSTRAP_PASSWORD:-admin}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deploy Rancher on a local kind cluster.

Options:
  --cluster-name <name>     Kind cluster name (default: rancher-demo)
  --k8s-version <version>   K8s version (default: v1.31.0)
  --hostname <fqdn>         Rancher hostname (default: rancher.local)
  --version <semver>        Rancher version (default: 2.10.3)
  --tls <source>            TLS source: selfsigned | letsencrypt (default: selfsigned)
  --bootstrap-password <p>  Admin password (default: admin)
  --help                    Show this help
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-name)     CLUSTER_NAME="$2"; shift 2 ;;
    --k8s-version)      K8S_VERSION="$2"; shift 2 ;;
    --hostname)         RANCHER_HOSTNAME="$2"; shift 2 ;;
    --version)          RANCHER_VERSION="$2"; shift 2 ;;
    --tls)              TLS_SOURCE="$2"; shift 2 ;;
    --bootstrap-password) BOOTSTRAP_PASSWORD="$2"; shift 2 ;;
    --help)             usage ;;
    *)                  error "Unknown option: $1"; usage ;;
  esac
done

header "Creating kind cluster: ${CLUSTER_NAME}"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  info "Cluster '${CLUSTER_NAME}' already exists. Skipping creation."
else
  cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30080
        hostPort: ${HTTP_NODE_PORT}
      - containerPort: 30443
        hostPort: ${HTTPS_NODE_PORT}
kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
EOF
fi

header "Installing NGINX Ingress Controller"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

if [[ "${TLS_SOURCE}" == "selfsigned" ]]; then
  export RANCHER_HOSTNAME="${RANCHER_HOSTNAME}"
  export K8S_DISTRO="kind"
fi

export RANCHER_VERSION="${RANCHER_VERSION}"
export BOOTSTRAP_PASSWORD="${BOOTSTRAP_PASSWORD}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/deploy-rancher.sh" \
  --hostname "${RANCHER_HOSTNAME}" \
  --version "${RANCHER_VERSION}" \
  --tls "${TLS_SOURCE}" \
  --k8s-distro kind \
  --replicas 1 \
  --bootstrap-password "${BOOTSTRAP_PASSWORD}"

header "Access Rancher"
echo ""
info "Add to your /etc/hosts:"
echo "  127.0.0.1 ${RANCHER_HOSTNAME}"
echo ""
info "Access URL:  https://${RANCHER_HOSTNAME}:${HTTPS_NODE_PORT}"
echo "  Username: admin"
echo "  Password: ${BOOTSTRAP_PASSWORD}"
echo ""
info "Or use port-forwarding:"
echo "  kubectl port-forward -n cattle-system svc/rancher 443:443"
echo "  https://localhost:443"
