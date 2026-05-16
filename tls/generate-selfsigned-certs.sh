#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-rancher.local}"
OUTPUT_DIR="${2:-./certs}"
DAYS="${DAYS:-3650}"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
error() { echo -e "${CYAN}[ERROR]${NC} $*"; }
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
header(){ echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

usage() {
  cat <<EOF
Usage: $0 [domain] [output-dir]

Generate self-signed TLS certificates for Rancher.

Arguments:
  domain        Domain name (default: rancher.local)
  output-dir    Output directory (default: ./certs)

Environment:
  DAYS          Certificate validity in days (default: 3650)

Example:
  $0 rancher.example.com ./my-certs
EOF
  exit 0
}

[[ "$1" == "--help" || "$1" == "-h" ]] && usage

header "Generating self-signed certificates for ${DOMAIN}"

mkdir -p "${OUTPUT_DIR}"

openssl req -x509 -nodes -days "${DAYS}" -newkey rsa:2048 \
  -keyout "${OUTPUT_DIR}/${DOMAIN}.key" \
  -out "${OUTPUT_DIR}/${DOMAIN}.crt" \
  -subj "/CN=${DOMAIN}/O=Rancher Self-Signed" \
  -addext "subjectAltName = DNS:${DOMAIN}" 2>/dev/null

info "Certificate:  ${OUTPUT_DIR}/${DOMAIN}.crt"
info "Private key:  ${OUTPUT_DIR}/${DOMAIN}.key"

# Create TLS secret for Rancher
if command -v kubectl &>/dev/null; then
  kubectl create secret tls tls-rancher-ingress \
    --namespace cattle-system \
    --key "${OUTPUT_DIR}/${DOMAIN}.key" \
    --cert "${OUTPUT_DIR}/${DOMAIN}.crt" \
    --dry-run=client -o yaml | kubectl apply -f -
  info "Created Kubernetes secret: cattle-system/tls-rancher-ingress"
fi

info "Done"
