#!/usr/bin/env bash
# Step 11: install the RAG app (chain server + playground UI).
# Requires NGC_API_KEY to already be exported (Step 5), and the NIM services (Step 9) and
# Milvus (Step 10) to already be Ready -- the values below point straight at their service names.
# This writes the values out to my-values.yaml (same content as rag-values.yaml in this folder)
# and installs with it, exactly as run on the live cluster.
set -euo pipefail

echo "${NGC_API_KEY:+set}"
: "${NGC_API_KEY:?NGC_API_KEY is not set -- run: source setup-ngc-key.sh}"

# Helm does not create the namespace for you unless you pass --create-namespace.
kubectl create namespace rag-sample

helm fetch https://helm.ngc.nvidia.com/nvidia/aiworkflows/charts/rag-app-multiturn-chatbot-24.08.tgz \
  --username='$oauthtoken' --password="$NGC_API_KEY"

cat <<'EOF' > my-values.yaml
query:
  env:
    APP_VECTORSTORE_URL: "http://milvus.milvus.svc.cluster.local:19530"
    APP_VECTORSTORE_NAME: "milvus"
    APP_LLM_SERVERURL: "meta-llama3-8b-instruct.nim-service.svc.cluster.local:8000"
    APP_LLM_MODELNAME: meta/llama-3.1-8b-instruct
    APP_LLM_MODELENGINE: nvidia-ai-endpoints
    APP_EMBEDDINGS_SERVERURL: "nv-embedqa-e5-v5.nim-service.svc.cluster.local:8000"
    APP_EMBEDDINGS_MODELNAME: nvidia/nv-embedqa-e5-v5
    APP_EMBEDDINGS_MODELENGINE: nvidia-ai-endpoints
    APP_RANKING_SERVERURL: "llama-nemotron-rerank-1b-v2.nim-service.svc.cluster.local:8000"
    APP_RANKING_MODELNAME: nvidia/llama-nemotron-rerank-1b-v2
    APP_RANKING_MODELENGINE: nvidia-ai-endpoints
    COLLECTION_NAME: multi_turn_rag
EOF

helm install multiturn-rag rag-app-multiturn-chatbot-24.08.tgz -n rag-sample \
  --set imagePullSecret.password="$NGC_API_KEY" -f my-values.yaml

echo "Validate with:"
echo "  kubectl get pods,svc -n rag-sample -w"
