#!/usr/bin/env bash
# Step 3: install k3s (single-node Kubernetes), point its data dir at the large ephemeral
# disk, and install Helm. Run this after install-container-toolkit.sh.
#
# The 100GB root disk is too small for model caches, so k3s's data directory is symlinked to
# the 1.5TB /ephemeral disk first. Note: Hyperstack wipes /ephemeral on VM hibernate/delete,
# so finish the whole deployment in one sitting, or point this at a persistent volume instead.
#
# Traefik (k3s's bundled ingress) is left at its default here -- it's simply unused, since this
# guide exposes the UI with a NodePort instead. Pass --disable=traefik if you want it removed.
set -euo pipefail

sudo mkdir -p /ephemeral/rancher
sudo ln -s /ephemeral/rancher /var/lib/rancher
df -h /var/lib/rancher/

curl -sfL https://get.k3s.io | sh -s - --default-runtime=nvidia
sudo grep nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml

mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER" ~/.kube/config
echo 'export KUBECONFIG=$HOME/.kube/config' >> ~/.bashrc
export KUBECONFIG=$HOME/.kube/config

sudo apt install -y jq

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

echo "Validate with:"
echo "  kubectl get nodes"
echo "  kubectl get storageclass"
echo "  kubectl get pods -A"
echo "  helm version"
