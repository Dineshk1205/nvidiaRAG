#!/usr/bin/env bash
# Step 10: make the chain server pass the LLM model name to a locally hosted NIM.
#
# Why: the chart's client (langchain-nvidia-ai-endpoints 0.1.6) picks the model itself for a
# local NIM, and it rejects the NIM 2.x model list ("No locally hosted model was found").
# This script adds `model=settings.llm.model_name` to that call and mounts the fixed file.
#
# Run it again after any `helm upgrade` or reinstall of the RAG app, because that overwrites the patch.
set -euo pipefail

NS=rag-sample
DEPLOY=chain-server-multi-turn

# Copy the current file out of the pod (after a fresh install this is the original; if the patch is already mounted it is the patched one).
kubectl exec -n "$NS" deploy/"$DEPLOY" -- cat /opt/RAG/src/chain_server/utils.py > utils.py

python3 - <<'EOF'
s = open("utils.py").read()
old = 'base_url=f"http://{settings.llm.server_url}/v1",\n                temperature='
new = 'base_url=f"http://{settings.llm.server_url}/v1",\n                model=settings.llm.model_name,\n                temperature='
if new in s:
    print("utils.py already contains the fix; re-applying the same file")
else:
    assert s.count(old) == 1, "expected call not found exactly once; stop and check utils.py"
    open("utils.py", "w").write(s.replace(old, new))
    print("utils.py patched")
EOF

kubectl create configmap chain-utils-patch -n "$NS" --from-file=utils.py --dry-run=client -o yaml | kubectl apply -f -

CN=$(kubectl get deploy "$DEPLOY" -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].name}')
kubectl patch deployment "$DEPLOY" -n "$NS" -p "{\"spec\":{\"template\":{\"spec\":{\"volumes\":[{\"name\":\"utils-patch\",\"configMap\":{\"name\":\"chain-utils-patch\"}}],\"containers\":[{\"name\":\"$CN\",\"volumeMounts\":[{\"name\":\"utils-patch\",\"mountPath\":\"/opt/RAG/src/chain_server/utils.py\",\"subPath\":\"utils.py\"}]}]}}}}"
kubectl rollout status deploy/"$DEPLOY" -n "$NS"

echo "Check: kubectl exec -i -n $NS deploy/$DEPLOY -- /usr/bin/python3.10 -c 'import sys; sys.path.insert(0,\"/opt\"); from RAG.src.chain_server.utils import get_llm; print(get_llm().invoke(\"hi\").content)'"
