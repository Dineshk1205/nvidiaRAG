#!/usr/bin/env bash
# Step 2: install the NVIDIA Container Toolkit.
# Run this after the driver (install-nvidia-driver.sh) and before k3s (install-k3s-helm.sh) --
# k3s only wires up the NVIDIA container runtime if it finds the toolkit already installed
# when k3s itself starts. Docker is not needed anywhere in this stack.
set -euo pipefail

sudo apt-get install -y --no-install-recommends ca-certificates curl gnupg2

curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

echo "Validate with:"
echo "  command -v nvidia-container-runtime"
echo "  nvidia-ctk --version"
