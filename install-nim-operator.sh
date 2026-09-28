#!/usr/bin/env bash
# Step 6: install the NIM Operator and create the NGC secrets it needs to pull models/images.
# Requires NGC_API_KEY to already be exported in this shell -- run `source setup-ngc-key.sh`
# first (Step 5) if you haven't.
set -euo pipefail

: "${NGC_API_KEY:?NGC_API_KEY is not set -- run: source setup-ngc-key.sh}"

kubectl create namespace nim-operator
helm upgrade --install nim-operator nvidia/k8s-nim-operator -n nim-operator --version=3.1.2

kubectl create namespace nim-service

kubectl create secret -n nim-service docker-registry ngc-secret --docker-server=nvcr.io \
  --docker-username='$oauthtoken' --docker-password="$NGC_API_KEY"

kubectl create secret -n nim-service generic ngc-api-secret --from-literal=NGC_API_KEY="$NGC_API_KEY"

echo "Validate with:"
echo "  kubectl get pods -n nim-operator"
echo "  kubectl get secret -n nim-service ngc-secret ngc-api-secret"
