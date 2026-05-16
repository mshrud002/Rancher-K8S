#!/usr/bin/env bash
set -euo pipefail

RANCHER_VERSION="${RANCHER_VERSION:-2.10.3}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.local}"
RANCHER_REPLICAS="${RANCHER_REPLICAS:-3}"
TLS_SOURCE="${TLS_SOURCE:-selfsigned}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-1.16.3}"
NAMESPACE="${NAMESPACE:-cattle-system}"
BOOTSTRAP_PASSWORD="${BOOTSTRAP_PASSWORD:-}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
K8S_DISTRO="${K8S_DISTRO:-auto}"
OPENSHIFT_INGRESS="${OPENSHIFT_INGRESS:-false}"
DISABLE_PSP="${DISABLE_PSP:-false}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Deploy Rancher on any Kubernetes cluster.

Options:
  --hostname <fqdn>         Rancher hostname (default: rancher.local)
  --version <semver>        Rancher Helm chart version (default: 2.10.3)
  --replicas <num>          Number of Rancher replicas (default: 3)
  --tls <source>            TLS source: selfsigned | letsencrypt | secret (default: selfsigned)
  --letsencrypt-email <e>   Email for Let's Encrypt (required if --tls letsencrypt)
  --cert-manager-version    cert-manager version (default: 1.16.3)
  --namespace <ns>          Kubernetes namespace (default: cattle-system)
  --bootstrap-password <p>  Bootstrap password for admin login
  --k8s-distro <distro>     K8s distro: auto | kind | minikube | k3s | rke2 | openshift | aks | eks | gke
  --openshift-ingress       Use OpenShift Route instead of standard Ingress
  --disable-psp             Disable PodSecurityPolicy (required for OpenShift)
  --help                    Show this help

Examples:
  $0 --hostname rancher.example.com --tls letsencrypt --letsencrypt-email admin@example.com
  $0 --hostname rancher.local --tls selfsigned
  $0 --k8s-distro kind --hostname rancher.local --tls selfsigned
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname)            RANCHER_HOSTNAME="$2"; shift 2 ;;
    --version)             RANCHER_VERSION="$2"; shift 2 ;;
    --replicas)            RANCHER_REPLICAS="$2"; shift 2 ;;
    --tls)                 TLS_SOURCE="$2"; shift 2 ;;
    --letsencrypt-email)   LETSENCRYPT_EMAIL="$2"; shift 2 ;;
    --cert-manager-version) CERT_MANAGER_VERSION="$2"; shift 2 ;;
    --namespace)           NAMESPACE="$2"; shift 2 ;;
    --bootstrap-password)  BOOTSTRAP_PASSWORD="$2"; shift 2 ;;
    --k8s-distro)          K8S_DISTRO="$2"; shift 2 ;;
    --openshift-ingress)   OPENSHIFT_INGRESS="true"; shift ;;
    --disable-psp)         DISABLE_PSP="true"; shift ;;
    --help)                usage ;;
    *)                     error "Unknown option: $1"; usage ;;
  esac
done

check_prereqs() {
  header "Checking prerequisites"

  if ! command -v kubectl &>/dev/null; then
    error "kubectl is not installed. Install it first: https://kubernetes.io/docs/tasks/tools/"
    exit 1
  fi
  info "kubectl found: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

  if ! command -v helm &>/dev/null; then
    warn "Helm not found — installing..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
  info "Helm found: $(helm version --short)"

  if ! kubectl cluster-info dump --request-timeout=5s &>/dev/null 2>&1; then
    error "Cannot connect to a Kubernetes cluster. Check your kubeconfig."
    exit 1
  fi
  info "Connected to cluster: $(kubectl config current-context)"
}

detect_distro() {
  if [[ "$K8S_DISTRO" != "auto" ]]; then
    return
  fi

  local ctx
  ctx="$(kubectl config current-context 2>/dev/null)"

  if [[ "$ctx" == kind-* ]]; then
    K8S_DISTRO="kind"
  elif [[ "$ctx" == minikube ]]; then
    K8S_DISTRO="minikube"
  elif kubectl get node 2>/dev/null | grep -qi "k3s"; then
    K8S_DISTRO="k3s"
  elif kubectl get ns kube-system -o yaml 2>/dev/null | grep -qi "rke2"; then
    K8S_DISTRO="rke2"
  elif kubectl get clusterrolebindings,namespaces -o wide 2>/dev/null | grep -qi "openshift" || \
       kubectl api-resources 2>/dev/null | grep -qi "route.openshift.io"; then
    K8S_DISTRO="openshift"
    DISABLE_PSP="true"
  elif [[ "$ctx" =~ ^[a-z]+-cluster.*$ ]] || [[ "$ctx" =~ ^arn: ]]; then
    if kubectl get nodes 2>/dev/null | grep -qi "eks"; then
      K8S_DISTRO="eks"
    fi
  elif [[ "$ctx" == gke_* ]]; then
    K8S_DISTRO="gke"
  fi

  if [[ "$K8S_DISTRO" == "auto" ]]; then
    K8S_DISTRO="generic"
  fi
  info "Detected K8s distribution: ${K8S_DISTRO}"
}

install_cert_manager() {
  header "Installing cert-manager ${CERT_MANAGER_VERSION}"

  if kubectl get ns cert-manager &>/dev/null && \
     kubectl -n cert-manager get deploy cert-manager &>/dev/null; then
    info "cert-manager already installed. Skipping."
    return
  fi

  kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

  if [[ "${K8S_DISTRO}" == "openshift" ]]; then
    info "Applying OpenShift SCC anyuid for cert-manager..."
    oc adm policy add-scc-to-user anyuid -z cert-manager -n cert-manager 2>/dev/null || true
    oc adm policy add-scc-to-user anyuid -z cert-manager-cainjector -n cert-manager 2>/dev/null || true
    oc adm policy add-scc-to-user anyuid -z cert-manager-webhook -n cert-manager 2>/dev/null || true
  fi

  helm repo add jetstack https://charts.jetstack.io --force-update
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --version "v${CERT_MANAGER_VERSION}" \
    --set installCRDs=true \
    --wait \
    --timeout 15m

  info "Waiting for cert-manager to be ready..."
  kubectl -n cert-manager rollout status deploy/cert-manager --timeout=300s
  kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=300s
  kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=300s
}

install_rancher() {
  header "Deploying Rancher ${RANCHER_VERSION}"

  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  helm repo add rancher-latest https://releases.rancher.com/server-charts/latest --force-update
  helm repo update

  local helm_args=(
    --namespace "${NAMESPACE}"
    --set hostname="${RANCHER_HOSTNAME}"
    --set replicas="${RANCHER_REPLICAS}"
    --set bootstrapPassword="${BOOTSTRAP_PASSWORD}"
    --wait
    --timeout 15m
  )

  if [[ -n "${RANCHER_VERSION}" ]]; then
    helm_args+=(--version "${RANCHER_VERSION}")
  fi

  if [[ "${DISABLE_PSP}" == "true" || "${K8S_DISTRO}" == "openshift" ]]; then
    info "Disabling PodSecurityPolicy..."
    helm_args+=(--set global.cattle.psp.enabled=false)
  fi

  if [[ "${K8S_DISTRO}" == "openshift" && "${OPENSHIFT_INGRESS}" != "true" ]]; then
    info "Disabling standard ingress for OpenShift (using Route instead)..."
    helm_args+=(--set ingress.enabled=false)
  fi

  if [[ "${K8S_DISTRO}" == "openshift" ]]; then
    info "Adding OpenShift-specific Rancher settings..."
    helm_args+=(--set global.cattle.openshift.enabled=true)
  fi

  case "${TLS_SOURCE}" in
    selfsigned)
      info "Using self-signed TLS certificate"
      helm_args+=(--set ingress.tls.source=rancher)
      ;;
    letsencrypt)
      if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
        error "--letsencrypt-email is required when using letsencrypt TLS"
        exit 1
      fi
      info "Using Let's Encrypt TLS with email: ${LETSENCRYPT_EMAIL}"
      helm_args+=(
        --set ingress.tls.source=letsEncrypt
        --set letsEncrypt.email="${LETSENCRYPT_EMAIL}"
        --set letsEncrypt.ingressClass=nginx
      )
      ;;
    secret)
      info "Using existing TLS secret. Ensure a secret named 'tls-rancher-ingress' exists in ${NAMESPACE}"
      helm_args+=(--set ingress.tls.source=secret)
      ;;
    *)
      error "Unknown TLS source: ${TLS_SOURCE}. Options: selfsigned, letsencrypt, secret"
      exit 1
      ;;
  esac

  helm upgrade --install rancher rancher-latest/rancher "${helm_args[@]}"

  info "Waiting for Rancher rollout..."
  kubectl -n "${NAMESPACE}" rollout status deploy/rancher --timeout=600s

  if [[ "${K8S_DISTRO}" == "openshift" && "${OPENSHIFT_INGRESS}" != "true" ]]; then
    header "Creating OpenShift Route for Rancher"
    oc create route passthrough --service=rancher --port=https \
      --hostname="${RANCHER_HOSTNAME}" \
      -n "${NAMESPACE}" \
      --dry-run=client -o yaml | oc apply -f -
    info "OpenShift Route created for rancher service"
  fi
}

post_install() {
  header "Rancher deployment complete"

  echo "  Rancher URL:  https://${RANCHER_HOSTNAME}"
  echo "  Namespace:    ${NAMESPACE}"

  if [[ "${TLS_SOURCE}" == "selfsigned" ]] && [[ "${K8S_DISTRO}" == "kind" || "${K8S_DISTRO}" == "minikube" ]]; then
    echo ""
    warn "For local clusters, you may need port-forwarding:"
    echo "  kubectl -n ${NAMESPACE} port-forward svc/rancher 443:443"
    echo ""
    echo "  Then add to /etc/hosts:"
    echo "  127.0.0.1 ${RANCHER_HOSTNAME}"
    echo ""
    echo "  Access: https://${RANCHER_HOSTNAME}"
  fi

  if [[ -z "${BOOTSTRAP_PASSWORD}" ]]; then
    echo ""
    warn "Retrieving bootstrap password..."
    local bp=""
    bp=$(kubectl get secret --namespace "${NAMESPACE}" bootstrap-secret -o jsonpath="{.data.bootstrapPassword}" 2>/dev/null | base64 -d) || true
    if [[ -n "$bp" ]]; then
      echo "  Bootstrap password: ${bp}"
    else
      echo "  (retrieve it later with: kubectl get secret --namespace ${NAMESPACE} bootstrap-secret -o jsonpath='{.data.bootstrapPassword}' | base64 -d)"
    fi
  fi
}

main() {
  echo -e "${CYAN}"
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║      Rancher on Kubernetes Deployer       ║"
  echo "  ╚═══════════════════════════════════════════╝"
  echo -e "${NC}"

  check_prereqs
  detect_distro
  install_cert_manager
  install_rancher
  post_install
}

main
