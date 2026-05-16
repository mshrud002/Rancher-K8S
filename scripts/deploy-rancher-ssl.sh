#!/usr/bin/env bash
set -euo pipefail

# Deploy Rancher with a custom TLS certificate (from a file).

DOMAIN="${1:-}"
CERT_FILE="${2:-}"
KEY_FILE="${3:-}"

if [[ -z "$DOMAIN" || -z "$CERT_FILE" || -z "$KEY_FILE" ]]; then
  echo "Usage: $0 <domain> <cert-file> <key-file>"
  echo ""
  echo "Example:"
  echo "  $0 rancher.example.com /path/to/tls.crt /path/to/tls.key"
  exit 1
fi

for f in "$CERT_FILE" "$KEY_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: File not found: $f"
    exit 1
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret tls tls-rancher-ingress \
  --namespace cattle-system \
  --key "$KEY_FILE" \
  --cert "$CERT_FILE" \
  --dry-run=client -o yaml | kubectl apply -f -

export TLS_SOURCE=secret

"${SCRIPT_DIR}/deploy-rancher.sh" \
  --hostname "$DOMAIN" \
  --tls secret \
  --bootstrap-password "${BOOTSTRAP_PASSWORD:-admin}"
