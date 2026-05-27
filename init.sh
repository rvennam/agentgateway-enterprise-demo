#!/usr/bin/env bash
# Pre-demo setup. Run once before opening demo.ipynb.
#
# Deploys the workloads the demo points at:
#  - mock-llm:          vLLM-sim in the ai-models namespace, stands in for any OpenAI-compatible model
#  - httpbin:           echo server in the mcp-servers namespace (used by the token-exchange section)
#  - server-everything: @modelcontextprotocol/server-everything in the mcp-servers namespace
#
# Wires up the gateway plumbing that isn't itself a teaching moment:
#  - sts / sts-jwks AgentgatewayBackends (point at the in-cluster STS on :7777)
#  - HTTPRoute that exposes the STS through the gateway at /sts
#
# Usage:
#   ./init.sh         # deploy
#   ./init.sh down    # tear down

set -euo pipefail
NS=agentgateway-system

if [[ "${1:-}" == "down" ]]; then
  kubectl delete -n "$NS" \
    httproute/sts agbe/sts agbe/sts-jwks \
    --ignore-not-found
  kubectl delete ns ai-models mcp-servers --ignore-not-found
  exit 0
fi

kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ai-models
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mock-llm
  namespace: ai-models
spec:
  replicas: 1
  selector: {matchLabels: {app: mock-llm}}
  template:
    metadata: {labels: {app: mock-llm}}
    spec:
      containers:
      - name: vllm-sim
        image: ghcr.io/llm-d/llm-d-inference-sim:latest
        args: [--model, mock-llm, --port, "8000"]
        ports: [{containerPort: 8000}]
        readinessProbe:
          tcpSocket: {port: 8000}
          initialDelaySeconds: 2
          periodSeconds: 2
---
apiVersion: v1
kind: Service
metadata:
  name: mock-llm
  namespace: ai-models
spec:
  selector: {app: mock-llm}
  ports: [{port: 8000, targetPort: 8000}]
---
apiVersion: v1
kind: Namespace
metadata:
  name: mcp-servers
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: mcp-servers
spec:
  replicas: 1
  selector: {matchLabels: {app: httpbin}}
  template:
    metadata: {labels: {app: httpbin}}
    spec:
      containers:
      - name: httpbin
        image: mccutchen/go-httpbin:latest
        ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: mcp-servers
spec:
  selector: {app: httpbin}
  ports: [{port: 80, targetPort: 8080}]
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: server-everything
  namespace: mcp-servers
spec:
  replicas: 1
  selector: {matchLabels: {app: server-everything}}
  template:
    metadata: {labels: {app: server-everything}}
    spec:
      containers:
      - name: mcp-everything
        image: node:20-alpine
        command: [sh, -c]
        args:
        - |
          export NODE_OPTIONS="--max-old-space-size=10240 --max-semi-space-size=64"
          npx -y @modelcontextprotocol/server-everything streamableHttp
        ports: [{containerPort: 3001}]
        env: [{name: PORT, value: "3001"}]
---
apiVersion: v1
kind: Service
metadata:
  name: server-everything
  namespace: mcp-servers
spec:
  selector: {app: server-everything}
  ports: [{port: 80, targetPort: 3001}]
---
# Backends pointing at the in-cluster STS on :7777
# (sections 7 and 8 reference these to validate STS-issued JWTs)
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: sts
  namespace: $NS
spec:
  static:
    host: enterprise-agentgateway.agentgateway-system.svc.cluster.local
    port: 7777
---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: sts-jwks
  namespace: $NS
spec:
  static:
    host: enterprise-agentgateway.agentgateway-system.svc.cluster.local
    port: 7777
---
# Expose the STS through the gateway at /sts so clients can POST /sts/token
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: sts
  namespace: $NS
spec:
  parentRefs:
  - name: agentgateway-proxy
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /sts
    filters:
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /
    backendRefs:
    - name: sts
      group: agentgateway.dev
      kind: AgentgatewayBackend
EOF

kubectl rollout status -n ai-models deploy/mock-llm --timeout=180s
kubectl rollout status -n mcp-servers deploy/httpbin --timeout=180s
kubectl rollout status -n mcp-servers deploy/server-everything --timeout=180s
echo "init complete: workloads + STS plumbing ready"
