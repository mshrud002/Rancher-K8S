#!/usr/bin/env bash
set -euo pipefail

RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.apps.$(oc get ingress.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo 'localhost')}"
RANCHER_VERSION="${RANCHER_VERSION:-2.10.3}"
TLS_SOURCE="${TLS_SOURCE:-selfsigned}"
BOOTSTRAP_PASSWORD="${BOOTSTRAP_PASSWORD:-admin}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deploy Rancher on Red Hat OpenShift.

Options:
  --hostname <fqdn>         Rancher hostname (default: auto-detected from cluster)
  --version <semver>        Rancher Helm chart version (default: 2.10.3)
  --tls <source>            TLS source: selfsigned | letsencrypt | secret (default: selfsigned)
  --letsencrypt-email <e>   Email for Let's Encrypt (required if --tls letsencrypt)
  --bootstrap-password <p>  Admin password (default: admin)
  --help                    Show this help

Examples:
  $0
  $0 --hostname rancher-custom.apps.ocp.example.com --tls letsencrypt --letsencrypt-email admin@example.com
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname)            RANCHER_HOSTNAME="$2"; shift 2 ;;
    --version)             RANCHER_VERSION="$2"; shift 2 ;;
    --tls)                 TLS_SOURCE="$2"; shift 2 ;;
    --letsencrypt-email)   LETSENCRYPT_EMAIL="$2"; shift 2 ;;
    --bootstrap-password)  BOOTSTRAP_PASSWORD="$2"; shift 2 ;;
    --help)                usage ;;
    *)                     error "Unknown option: $1"; usage ;;
  esac
done

if ! command -v oc &>/dev/null; then
  error "OpenShift CLI (oc) is required. Install it first: https://mirror.openshift.com/pub/openshift-v4/clients/oc/"
  exit 1
fi

header "Verifying OpenShift cluster connection"
oc whoami || { error "Not logged into OpenShift. Run 'oc login' first."; exit 1; }
info "User: $(oc whoami)"
info "Server: $(oc whoami --show-server)"
info "Hostname: ${RANCHER_HOSTNAME}"

header "Applying SCC permissions for cert-manager"
for sa in cert-manager cert-manager-cainjector cert-manager-webhook; do
  oc adm policy add-scc-to-user anyuid -z "${sa}" -n cert-manager 2>/dev/null || true
done
oc adm policy add-scc-to-user anyuid -z rancher -n cattle-system 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${TLS_SOURCE}" == "letsencrypt" ]]; then
  "${SCRIPT_DIR}/deploy-rancher.sh" \
    --hostname "${RANCHER_HOSTNAME}" \
    --version "${RANCHER_VERSION}" \
    --tls letsencrypt \
    --letsencrypt-email "${LETSENCRYPT_EMAIL}" \
    --k8s-distro openshift \
    --bootstrap-password "${BOOTSTRAP_PASSWORD}" \
    --disable-psp
else
  "${SCRIPT_DIR}/deploy-rancher.sh" \
    --hostname "${RANCHER_HOSTNAME}" \
    --version "${RANCHER_VERSION}" \
    --tls "${TLS_SOURCE}" \
    --k8s-distro openshift \
    --bootstrap-password "${BOOTSTRAP_PASSWORD}" \
    --disable-psp
fi

header "Access Rancher on OpenShift"
echo ""
info "Access URL:  https://${RANCHER_HOSTNAME}"
echo "  Username: admin"
echo "  Password: ${BOOTSTRAP_PASSWORD}"
echo ""
info "Get Routes:"
echo "  oc get route rancher -n cattle-system"
