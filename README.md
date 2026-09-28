# NVIDIA RAG Pipeline on k3s (single node, 2× A100)

This repo deploys NVIDIA's NIM Operator RAG sample end to end on a single-node Kubernetes
cluster — no managed Kubernetes service, no multi-node setup, just k3s on one box with two
A100s. Everything here was run and verified on that setup: the driver, the GPU Operator, the
three NIM model services, Milvus, and the chat UI in front of it.

The short version of what it does: you upload a PDF, it gets chunked and embedded into a vector
database, and when you ask a question the pipeline retrieves the relevant chunks, reranks them,
and has a local LLM write the answer — all inside your own cluster. Nothing calls out to an
external API; there's no OpenAI or Anthropic key anywhere in this config.

## Architecture, in short

```
                     Browser
                        |
                        v
               rag-playground (UI)
                        |
                        v
                 chain-server  <-- the only piece that talks to the models and the DB
             /        |          \            \
            v         v           v             v
  nv-embedqa-e5-v5  llama-nemotron-  meta-llama-3.1-    Milvus
  (embedding NIM)   rerank-1b-v2     8b-instruct        (vector DB)
                     (reranking NIM)  (LLM NIM, vLLM)

  Ingest:  PDF -> chain-server chunks it -> embed -> store vectors in Milvus
  Ask:     question -> embed -> Milvus search -> rerank -> generate -> answer
```

Two Kubernetes operators sit underneath all of this and do the heavy lifting: the **GPU
Operator** exposes the physical GPUs to Kubernetes and time-slices them so three model services
can share two cards, and the **NIM Operator** turns the `NIMCache`/`NIMService` YAML files below
into running model pods — you never `docker pull` a model by hand.

## Before you start

You'll need an NGC account (free), a 2× A100 box running Ubuntu 24.04, and inbound access to
port 22 plus whatever NodePort you end up exposing the UI on, ideally locked to your own IP.

```bash
ssh -i <key> ubuntu@<public-ip>
```

Everything below assumes you're running commands from that shell, in this repo's directory, in
order — a few steps genuinely depend on the one before finishing, not just starting, and that's
called out as it comes up.

## Step-by-step

**1. Install the NVIDIA driver**
Run `install-nvidia-driver.sh`. It pulls the open-kernel driver (580+ branch, needed for CUDA 13)
from NVIDIA's own apt repo and reboots the machine at the end. If apt is busy with unattended
upgrades when you kick this off, give it a minute (`pgrep -a unattended-upgr`) and try again.
```bash
bash install-nvidia-driver.sh
```
Expect: after the reboot, `nvidia-smi` lists both A100s and driver 580+.

**2. Install the NVIDIA Container Toolkit**
Run `install-container-toolkit.sh`. This has to happen before k3s starts, since k3s only wires up
the NVIDIA container runtime if the toolkit is already present at boot. No Docker involved
anywhere in this stack.
```bash
bash install-container-toolkit.sh
```
Expect: `nvidia-ctk --version` and `command -v nvidia-container-runtime` both print something.

**3. Install k3s, kubectl and Helm**
Run `install-k3s-helm.sh`. It symlinks k3s's data directory over to a larger secondary disk first
(the root disk on most single-VM setups is too small once model weights start piling up),
installs k3s with
`--default-runtime=nvidia` so every pod gets the NVIDIA runtime without you setting
`runtimeClassName` everywhere, and installs Helm. It leaves k3s's bundled Traefik ingress alone —
it's just unused here, since the UI gets exposed with a plain NodePort instead.
```bash
bash install-k3s-helm.sh
```
Expect: `kubectl get nodes` shows `Ready`, `kubectl get storageclass` shows `local-path`, `helm
version` works.

**4. Install the GPU Operator**
Run `install-gpu-operator.sh`. It adds NVIDIA's NGC Helm repo (you'll need it again for the NIM
Operator) and installs the GPU Operator with its own driver and toolkit management turned off,
since both are already on the host from steps 1–2. Don't turn on GPU time-slicing yet — that's
step 8, and doing it now would confuse the model-caching step that comes before it.
```bash
bash install-gpu-operator.sh
```
Expect: `kubectl get clusterpolicy` shows `ready`, and allocatable `nvidia.com/gpu` reads `"2"`.
Optionally confirm with NVIDIA's own CUDA test pod:
```bash
kubectl apply -f gpu-test-pod.yaml
kubectl logs pod/cuda-vectoradd
```
which should end with `Test PASSED`.

**5. Generate and export your NGC API key**
Generate a free NGC API key once, in your browser — sign up for the NVIDIA Developer Program,
then head to `org.ngc.nvidia.com/setup/api-keys` and create a key with "NGC Catalog" and "Public
API Endpoints" scopes. Back in your shell, source `setup-ngc-key.sh` to hold that key for the
rest of this session — every step from here on that pulls a model or image from NGC needs it.
```bash
source setup-ngc-key.sh
```
It has to be *sourced*, not run as a script, or the exported variable never reaches your shell —
and you'll need to do this again for any new SSH session.
Expect: no error after pasting the key; `echo $NGC_API_KEY` prints something back.

**6. Install the NIM Operator and NGC secrets**
Run `install-nim-operator.sh`. It installs the NIM Operator from the repo added in step 4, then
creates the two secrets everything downstream needs: `ngc-secret` for pulling images, and
`ngc-api-secret` holding the key itself.
```bash
bash install-nim-operator.sh
```
Expect: the operator pod is `Running`, and both secrets show up under `nim-service`.

**7. Cache the three models**
Apply `nim-caches.yaml`. This kicks off downloads for the embedding model
(`nv-embedqa-e5-v5`), the reranker (`llama-nemotron-rerank-1b-v2` — needs its NGC-download env
vars, since its default puller is Hugging Face), and the LLM (`meta-llama-3.1-8b-instruct`, on
the vLLM engine). Do this before enabling GPU time-slicing, so model-profile matching still sees
the real, non-shared GPU.
```bash
kubectl apply -f nim-caches.yaml
```
Expect: `kubectl get nimcache -n nim-service` eventually shows all three `Ready`. If one gets
stuck, `kubectl describe nimcache` will usually point at a profile-matching failure — that's why
the embedding and reranker caches in this file carry no model filter; a filter was what caused
that failure on this hardware.

**8. Turn on GPU time-slicing**
Apply `time-slicing-config.yaml` and patch the cluster policy to pick it up. This turns the two
physical A100s into four schedulable `nvidia.com/gpu` slots — enough for three model services to
each get one, with room to spare. Worth knowing: there's no memory isolation between slots, it's
purely a scheduling trick.
```bash
kubectl apply -n gpu-operator -f time-slicing-config.yaml
kubectl patch clusterpolicies.nvidia.com/cluster-policy -n gpu-operator --type merge \
  -p '{"spec":{"devicePlugin":{"config":{"name":"time-slicing-config-all","default":"any"}}}}'
```
Expect: `kubectl get nodes -o json | jq '.items[].status.allocatable["nvidia.com/gpu"]'` prints
`"4"`.

**9. Start the three NIM services**
Apply `nim-services-retrieval.yaml` (embedding + reranker) first, and wait for both to be Ready
before applying `nim-service-llm.yaml`. The LLM is capped at 8192 tokens and roughly half a GPU's
memory, but it still needs to start after the other two so it doesn't grab memory they need.
```bash
kubectl apply -f nim-services-retrieval.yaml
kubectl get nimservice -n nim-service -w
kubectl apply -f nim-service-llm.yaml
```
Expect: all three show `Ready`. You can sanity-check one directly with
`kubectl port-forward -n nim-service svc/meta-llama3-8b-instruct 8000:8000` and then
`curl -s localhost:8000/v1/models`.

**10. Install Milvus (the vector database)**
Run `install-milvus.sh`. It writes out the Helm values (swapping the chart's default MinIO image
for a community fork, `pgsty/silo`, since Docker Hub and Quay both stopped serving public MinIO
images), adds the Zilliztech Helm repo, and installs Milvus in standalone mode.
```bash
bash install-milvus.sh
```
Expect: `kubectl get pods,svc -n milvus` shows every pod `Running` and a `milvus` service
listening on port 19530.

**11. Install the RAG app (chain server + playground UI)**
Run `install-rag-app.sh`. It creates the `rag-sample` namespace (Helm won't do this for you
unless you pass `--create-namespace`), fetches NVIDIA's public
`rag-app-multiturn-chatbot-24.08` chart from NGC, and installs it with values that point the
chain server at the exact service names from steps 9 and 10 — same content as `rag-values.yaml`
in this repo, if you want to read it separately.
```bash
bash install-rag-app.sh
```
Expect: `kubectl get pods,svc -n rag-sample -w` shows `chain-server` and `rag-playground` both
`Running`.

**12. Patch the chain server's model name (required, not optional)**
Run `patch-chain-server.sh`. Here's the thing this step fixes: the chart's bundled client
(`langchain-nvidia-ai-endpoints`) tries to auto-detect the model name from a locally hosted
NIM's `/v1/models` response, and that auto-detection fails against current NIM versions with
"No locally hosted model was found" — every single chat request errors out without this patch.
The script mounts a one-line fix over `utils.py` that passes the model name explicitly instead of
relying on auto-detection. You'll need to re-run it after any reinstall or upgrade of the RAG
chart, since that overwrites the patch.
```bash
bash patch-chain-server.sh
```
Expect: the one-liner the script prints at the end comes back with a real answer instead of an
error.

**13. Expose the UI and take it for a spin**
Patch the playground service to `NodePort` (or just note whatever port Kubernetes already picked
for you), and open an inbound rule for that exact port from your own IP. A single node doesn't
need an ingress controller for this.
```bash
kubectl patch svc rag-playground-multiturn-rag -n rag-sample -p '{"spec":{"type":"NodePort"}}'
kubectl get svc -n rag-sample rag-playground-multiturn-rag
```
Expect: `http://<public-ip>:<nodeport>/` loads, and a PDF you upload gets answered using content
pulled from it. The UI only takes PDF uploads — a `.txt` file needs converting first, or posting
straight to the chain server's API.

## A few things worth knowing

- Time-slicing gives you more schedulable GPU slots, not more GPU memory — if things get tight,
  lower `NIM_MAX_MODEL_LEN` or run fewer services concurrently rather than assuming you have
  headroom you don't.
- The GPU Operator doesn't have an official k3s install guide (only general platform support is
  validated) — if something fails in step 4, the operator's own troubleshooting page is the best
  next stop.
- Every piece of processing — embedding, vector search, reranking, generation — happens inside
  this cluster. There's genuinely no external API call anywhere in the pipeline.

## Quick health check, any time

```bash
kubectl get pods -A                                # everything should be Running/Completed
kubectl get nimcache,nimservice -n nim-service      # model status
kubectl get pods,svc -n milvus                      # vector DB status
kubectl get pods,svc -n rag-sample                  # UI + chain-server status
nvidia-smi                                          # live GPU memory per process
```

## Versions this was actually tested against

k3s `v1.36.4+k3s1`, NVIDIA driver `580.178.04`, GPU Operator `v26.7.1`, NIM Operator `3.1.2`,
Milvus chart `5.0.28` (app `3.0.1`, unpinned — whatever `helm repo update` resolves to today may
differ), RAG app chart `rag-app-multiturn-chatbot-24.08`. Model images were pulled at `:latest`
and verified working on that date — if a later `:latest` pull behaves differently, pinning to a
specific digest is the fix (`sudo k3s crictl inspecti <image>` gets you the full digest to pin).
