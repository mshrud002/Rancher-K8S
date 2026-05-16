#!/usr/bin/env bash
set -euo pipefail

K3S_VERSION="${K3S_VERSION:-v1.31.2+k3s1}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.local}"
RANCHER_VERSION="${RANCHER_VERSION:-2.10.3}"
TLS_SOURCE="${TLS_SOURCE:-selfsigned}"
BOOTSTRAP_PASSWORD="${BOOTSTRAP_PASSWORD:-admin}"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deploy Rancher on a local k3s cluster.

Options:
  --k3s-version <version>   K3s version (default: v1.31.2+k3s1)
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
    --k3s-version)       K3S_VERSION="$2"; shift 2 ;;
    --hostname)          RANCHER_HOSTNAME="$2"; shift 2 ;;
    --version)           RANCHER_VERSION="$2"; shift 2 ;;
    --tls)               TLS_SOURCE="$2"; shift 2 ;;
    --bootstrap-password) BOOTSTRAP_PASSWORD="$2"; shift 2 ;;
    --help)              usage ;;
    *)                   error "Unknown option: $1"; usage ;;
  esac
done

if ! command -v k3s &>/dev/null; then
  header "Installing K3s ${K3S_VERSION}"
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_EXEC="--disable traefik --write-kubeconfig-mode 644" \
    sh -
else
  info "K3s already installed at $(which k3s)"
fi

export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

header "Waiting for K3s to be ready"
sleep 10
kubectl wait --for=condition=Ready nodes --all --timeout=120s

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/deploy-rancher.sh" \
  --hostname "${RANCHER_HOSTNAME}" \
  --version "${RANCHER_VERSION}" \
  --tls "${TLS_SOURCE}" \
  --k8s-distro k3s \
  --replicas 1 \
  --bootstrap-password "${BOOTSTRAP_PASSWORD}"

header "Access Rancher"
echo ""
info "Access URL:  https://${RANCHER_HOSTNAME}"
echo "  Username: admin"
echo "  Password: ${BOOTSTRAP_PASSWORD}"
echo ""
info "Add to /etc/hosts if needed:"
echo "  127.0.0.1 ${RANCHER_HOSTNAME}"
