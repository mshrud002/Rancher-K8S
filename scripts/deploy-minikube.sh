#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-rancher-demo}"
CPUS="${CPUS:-4}"
MEMORY="${MEMORY:-8192}"
K8S_VERSION="${K8S_VERSION:-v1.31.0}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.local}"
RANCHER_VERSION="${RANCHER_VERSION:-2.10.3}"
TLS_SOURCE="${TLS_SOURCE:-selfsigned}"
BOOTSTRAP_PASSWORD="${BOOTSTRAP_PASSWORD:-admin}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deploy Rancher on a local minikube cluster.

Options:
  --cluster-name <name>     Minikube profile name (default: rancher-demo)
  --cpus <num>              CPUs (default: 4)
  --memory <mb>             Memory in MB (default: 8192)
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
    --cluster-name)      CLUSTER_NAME="$2"; shift 2 ;;
    --cpus)              CPUS="$2"; shift 2 ;;
    --memory)            MEMORY="$2"; shift 2 ;;
    --k8s-version)       K8S_VERSION="$2"; shift 2 ;;
    --hostname)          RANCHER_HOSTNAME="$2"; shift 2 ;;
    --version)           RANCHER_VERSION="$2"; shift 2 ;;
    --tls)               TLS_SOURCE="$2"; shift 2 ;;
    --bootstrap-password) BOOTSTRAP_PASSWORD="$2"; shift 2 ;;
    --help)              usage ;;
    *)                   error "Unknown option: $1"; usage ;;
  esac
done

header "Creating minikube cluster: ${CLUSTER_NAME}"
minikube start \
  --profile "${CLUSTER_NAME}" \
  --cpus "${CPUS}" \
  --memory "${MEMORY}" \
  --kubernetes-version "${K8S_VERSION}" \
  --addons ingress

header "Enabling minikube tunnel (background)"
minikube tunnel --profile "${CLUSTER_NAME}" &>/dev/null &
MINIKUBE_PID=$!
info "minikube tunnel PID: ${MINIKUBE_PID}"

header "Adding ${RANCHER_HOSTNAME} to minikube /etc/hosts"
minikube ssh --profile "${CLUSTER_NAME}" -- \
  "echo '127.0.0.1 ${RANCHER_HOSTNAME}' | sudo tee -a /etc/hosts" &>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/deploy-rancher.sh" \
  --hostname "${RANCHER_HOSTNAME}" \
  --version "${RANCHER_VERSION}" \
  --tls "${TLS_SOURCE}" \
  --k8s-distro minikube \
  --replicas 1 \
  --bootstrap-password "${BOOTSTRAP_PASSWORD}"

header "Access Rancher"
echo ""
info "Access URL:  https://${RANCHER_HOSTNAME}"
echo "  Username: admin"
echo "  Password: ${BOOTSTRAP_PASSWORD}"
echo ""
info "Run in another terminal if needed:"
echo "  minikube tunnel --profile ${CLUSTER_NAME}"
