#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-cattle-system}"
REMOVE_CERT_MANAGER="${REMOVE_CERT_MANAGER:-false}"
REMOVE_CRDS="${REMOVE_CRDS:-false}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Uninstall Rancher and optionally cert-manager from a Kubernetes cluster.

Options:
  --namespace <ns>         Rancher namespace (default: cattle-system)
  --remove-cert-manager    Also remove cert-manager (default: false)
  --remove-crds            Also remove Rancher CRDs (default: false)
  --help                   Show this help

Examples:
  $0
  $0 --remove-cert-manager
  $0 --remove-cert-manager --remove-crds
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)           NAMESPACE="$2"; shift 2 ;;
    --remove-cert-manager) REMOVE_CERT_MANAGER="true"; shift ;;
    --remove-crds)         REMOVE_CRDS="true"; shift ;;
    --help)                usage ;;
    *)                     error "Unknown option: $1"; usage ;;
  esac
done

if ! command -v kubectl &>/dev/null; then
  error "kubectl is required"
  exit 1
fi

header "Uninstalling Rancher"

if helm list -n "${NAMESPACE}" 2>/dev/null | grep -q rancher; then
  info "Deleting Rancher Helm release..."
  helm uninstall rancher -n "${NAMESPACE}" --wait || true
else
  warn "No Rancher Helm release found in namespace ${NAMESPACE}"
fi

info "Deleting Rancher namespace ${NAMESPACE}..."
kubectl delete ns "${NAMESPACE}" --ignore-not-found --wait=false &

info "Deleting Rancher CRDs..."
kubectl delete crd -l app.kubernetes.io/name=rancher --ignore-not-found 2>/dev/null || true

if [[ "${REMOVE_CERT_MANAGER}" == "true" ]]; then
  header "Removing cert-manager"

  helm uninstall cert-manager -n cert-manager --wait 2>/dev/null || true
  kubectl delete ns cert-manager --ignore-not-found --wait=false

  info "Deleting cert-manager CRDs..."
  kubectl delete crd \
    -l app.kubernetes.io/instance=cert-manager \
    --ignore-not-found 2>/dev/null || true
  kubectl delete crd \
    -l app.kubernetes.io/component=controller \
    --ignore-not-found 2>/dev/null || true
fi

if [[ "${REMOVE_CRDS}" == "true" ]]; then
  header "Removing all Rancher-related CRDs"
  for crd in $(kubectl get crd 2>/dev/null | awk '/\.cattle\.io/ {print $1}'); do
    info "Deleting CRD: ${crd}"
    kubectl delete crd "${crd}" --ignore-not-found &
  done
fi

info "Uninstall complete"
echo ""
info "To also destroy local cluster (kind):  kind delete cluster --name rancher-demo"
info "To also destroy local cluster (minikube): minikube delete --profile rancher-demo"
info "To also destroy local cluster (k3s):   sudo /usr/local/bin/k3s-uninstall.sh"
