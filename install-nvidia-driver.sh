#!/usr/bin/env bash
# Step 1: install the NVIDIA driver (open-kernel, 580+ branch, for CUDA 13).
# Ubuntu 24.04 is assumed below; on 22.04 replace ubuntu2404 with ubuntu2204 in the URL.
set -euo pipefail

sudo apt update
sudo apt install -y linux-headers-"$(uname -r)"

wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt update
sudo apt install -y nvidia-driver-pinning-580 nvidia-driver-assistant
nvidia-driver-assistant
sudo apt install -y nvidia-open

echo "Driver packages installed. Rebooting now to load them..."
sudo reboot
