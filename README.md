# RAG AI Knowledge Assistant — Kubernetes Deployment

Production-grade Kubernetes deployment of the [RAG AI Knowledge Assistant](https://github.com/Kk-1020) built for the University of Toledo. The system answers natural-language queries over institutional documents using **LangChain + FAISS vector search + Mistral**, exposed via a **C# REST microservice**.

This repo demonstrates end-to-end container orchestration: multi-service Deployments, PersistentVolumeClaims for FAISS index durability, health probes, zero-downtime rolling updates, and a reusable Helm chart — runnable locally on minikube or on any production cluster.

---

## Architecture

```
                        ┌─────────────────────────────────────┐
                        │         Kubernetes Cluster           │
                        │           (namespace: rag-assistant) │
                        │                                      │
  User / Browser  ──►  Ingress (nginx)                        │
                        │    /         →  rest-backend-svc     │
                        │    /rag      →  rag-api-svc          │
                        │                                      │
                        │  ┌─────────────────┐                 │
                        │  │  rest-backend   │  (C# ASP.NET)   │
                        │  │  :5000          │                 │
                        │  └────────┬────────┘                 │
                        │           │  cluster-internal DNS     │
                        │  ┌────────▼────────┐                 │
                        │  │   rag-api       │  (Python)        │
                        │  │   :8000         │  LangChain       │
                        │  │                 │  FAISS           │
                        │  │  ┌─────────┐   │  Mistral         │
                        │  │  │  PVC    │   │                  │
                        │  │  │ faiss/  │   │                  │
                        │  │  └─────────┘   │                  │
                        │  └─────────────────┘                 │
                        └─────────────────────────────────────┘
```

| Component | Tech | Replicas | Port |
|---|---|---|---|
| `rag-api` | Python · LangChain · FAISS · Mistral | 2 | 8000 |
| `rest-backend` | C# ASP.NET Core | 1 | 5000 |
| `faiss-index-pvc` | PersistentVolumeClaim | — | — |

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| [minikube](https://minikube.sigs.k8s.io/docs/start/) | ≥ 1.32 | `brew install minikube` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | ≥ 1.28 | `brew install kubectl` |
| [Helm](https://helm.sh/docs/intro/install/) | ≥ 3.14 | `brew install helm` |
| Docker | ≥ 24 | [docker.com](https://www.docker.com/) |

---

## Quickstart — Plain YAML (minikube)

### 1. Start minikube and enable ingress

```bash
minikube start --cpus=4 --memory=8g
minikube addons enable ingress
```

### 2. Point your shell at minikube's Docker daemon

```bash
eval $(minikube docker-env)
```

### 3. Build the images inside minikube

```bash
# From your project root (where Dockerfiles live)
docker build -t rag-api:latest    -f Dockerfile.rag     .
docker build -t rest-backend:latest -f Dockerfile.backend .
```

### 4. Apply the manifests

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/rag-api-deployment.yaml
kubectl apply -f k8s/rag-api-service.yaml
kubectl apply -f k8s/rest-backend-deployment.yaml
kubectl apply -f k8s/rest-backend-service.yaml
kubectl apply -f k8s/ingress.yaml
```

### 5. Wait for pods to be ready

```bash
kubectl get pods -n rag-assistant --watch
```

All pods should reach `Running` with `2/2` or `1/1` ready containers.

### 6. Configure local DNS and open the app

```bash
# Add minikube IP to /etc/hosts
echo "$(minikube ip) rag-assistant.local" | sudo tee -a /etc/hosts

# Open in browser
open http://rag-assistant.local
```

---

## Quickstart — Helm

```bash
# Install the chart into the rag-assistant namespace
helm upgrade --install rag-assistant ./helm/rag-assistant \
  --namespace rag-assistant \
  --create-namespace \
  --wait

# Check the release
helm status rag-assistant -n rag-assistant
```

### Override values at install time

```bash
# Scale out rag-api replicas and change log level
helm upgrade rag-assistant ./helm/rag-assistant \
  --namespace rag-assistant \
  --set ragApi.replicaCount=4 \
  --set config.logLevel=DEBUG
```

### Uninstall

```bash
helm uninstall rag-assistant -n rag-assistant
kubectl delete namespace rag-assistant   # also removes the PVC
```

---

## Repository Layout

```
.
├── k8s/                            # Plain Kubernetes manifests
│   ├── namespace.yaml
│   ├── configmap.yaml              # Shared app configuration
│   ├── pvc.yaml                    # FAISS index persistence (2 Gi)
│   ├── rag-api-deployment.yaml     # Python inference service (2 replicas)
│   ├── rag-api-service.yaml
│   ├── rest-backend-deployment.yaml # C# REST microservice
│   ├── rest-backend-service.yaml
│   └── ingress.yaml                # nginx ingress with LLM-friendly timeouts
│
└── helm/
    └── rag-assistant/
        ├── Chart.yaml
        ├── values.yaml             # All tuneable parameters in one place
        └── templates/
            ├── _helpers.tpl        # Named template helpers
            ├── configmap.yaml
            ├── pvc.yaml
            ├── deployments.yaml    # Both services in one file
            └── services.yaml      # ClusterIP services + Ingress
```

---

## Key Design Decisions

### Zero-downtime rolling updates
Both Deployments use `maxUnavailable: 0` — Kubernetes always brings up a new pod before terminating an old one. Combined with readiness probes, the service is never unavailable during a redeploy.

### FAISS index durability via PVC
The FAISS vector index is mounted from a `PersistentVolumeClaim`, not baked into the image. This means the index survives pod restarts and can be pre-populated outside the container lifecycle.

### Non-root security context
All pods run as `uid 1000` with `runAsNonRoot: true`. This follows the principle of least privilege — a compromised container cannot write to system paths or escalate privileges.

### ConfigMap-driven configuration
All tuneable parameters (model name, chunk size, log level, service URLs) are externalised into a `ConfigMap`. No application code needs to change when deployment parameters change — a `kubectl apply` or `helm upgrade` is sufficient.

### Ingress timeout for LLM workloads
nginx's default 60-second proxy timeout is too short for LLM inference. The Ingress sets `proxy-read-timeout: 300` to handle slow first-token latency without the gateway killing the connection.

---

## Useful Commands

```bash
# Tail logs from all rag-api pods
kubectl logs -n rag-assistant -l app=rag-api --follow

# Exec into a pod for debugging
kubectl exec -it -n rag-assistant deploy/rag-api -- /bin/sh

# Describe a pod (shows resource usage, probe results, events)
kubectl describe pod -n rag-assistant -l app=rag-api

# Check PVC binding status
kubectl get pvc -n rag-assistant

# Port-forward rag-api directly (bypass ingress)
kubectl port-forward -n rag-assistant svc/rag-api-svc 8000:8000

# Port-forward REST backend
kubectl port-forward -n rag-assistant svc/rest-backend-svc 5000:5000
```

---

## Configuration Reference

All values configurable in `helm/rag-assistant/values.yaml`:

| Key | Default | Description |
|---|---|---|
| `ragApi.replicaCount` | `2` | Number of Python inference pods |
| `ragApi.resources.limits.memory` | `4Gi` | Memory ceiling per pod |
| `config.modelName` | `mistral` | LLM model identifier |
| `config.chunkSize` | `512` | Token chunk size for document splitting |
| `config.topKResults` | `5` | Top-K chunks retrieved per query |
| `persistence.size` | `2Gi` | FAISS index PVC capacity |
| `ingress.host` | `rag-assistant.local` | Hostname for local development |
| `ingress.proxyTimeoutSeconds` | `300` | nginx proxy timeout (LLM-aware) |

---

## Related

- [RAG AI Knowledge Assistant (main project)](https://github.com/Kk-1020)
- [Motor Fault Detection — 1D Residual CNN](https://github.com/Kk-1020)
- [Fixed-Point Math Library (C / CORDIC)](https://github.com/Kk-1020)

---

## License

MIT
