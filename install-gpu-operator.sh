#!/usr/bin/env bash
# Step 4: install the GPU Operator.
# Adds NVIDIA's NGC Helm repo (first use -- the GPU Operator and NIM Operator charts both live
# there), then installs the GPU Operator with its own driver and toolkit disabled, since both are
# already on the host from Steps 1-2. 
set -euo pipefail

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

helm install --wait --generate-name -n gpu-operator --create-namespace nvidia/gpu-operator \
  --version=v26.7.1 --set driver.enabled=false --set toolkit.enabled=false

echo "Validate with:"
echo "  kubectl get clusterpolicy"
echo "  kubectl get nodes -o json | jq '.items[].status.allocatable[\"nvidia.com/gpu\"]'   # expect \"2\""
echo "  kubectl apply -f gpu-test-pod.yaml && kubectl logs pod/cuda-vectoradd   # expect 'Test PASSED'"
