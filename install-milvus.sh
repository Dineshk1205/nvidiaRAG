#!/usr/bin/env bash
# Step 10: install Milvus (vector database): one etcd pod, one MinIO-compatible store, one
# Milvus pod. Writes the values below to milvus-values.yaml, then installs with them.
set -euo pipefail

cat <<'EOF' > milvus-values.yaml
cluster:
  enabled: false
pulsarv3:
  enabled: false
standalone:
  messageQueue: woodpecker
woodpecker:
  enabled: true
streaming:
  enabled: true
etcd:
  replicaCount: 1
minio:
  mode: standalone
  # MinIO stopped publishing public images (Docker Hub and quay.io both refuse pulls),
  # so the chart's default image fails with ImagePullBackOff.
  # pgsty/silo is a community fork of MinIO that worked with this chart.
  image:
    repository: docker.io/pgsty/silo
    tag: RELEASE.2026-09-16T00-00-00Z
EOF

helm repo add zilliztech https://zilliztech.github.io/milvus-helm/
helm repo update

helm install milvus zilliztech/milvus -n milvus --create-namespace -f milvus-values.yaml

echo "Validate with:"
echo "  kubectl get pods,svc -n milvus"
