# Enterprise Agentgateway Demo

A 10–20 minute walkthrough of what Solo's enterprise [agentgateway](https://docs.solo.io/agentgateway/) does for AI traffic — multi-LLM routing, failover, guardrails, rate limiting, MCP proxying, token exchange, tool authorization, observability, and waypoint mode. It runs as a Jupyter notebook (`demo.ipynb`) against a live cluster.

## What's covered

| # | Section | Shows |
|---|---------|-------|
| 1 | **Multi-LLM routing** | One gateway in front of multiple model providers (Anthropic + a self-hosted OpenAI-compatible model) |
| 2 | **LLM failover** | Priority groups + automatic eviction when a provider fails |
| 3 | **Built-in guardrails** | Block prompt injection and PII at the gateway |
| 4 | **Global token rate limiting** | Redis-backed shared quota across proxy replicas |
| 5 | **MCP routing** | Proxy an MCP server |
| 6 | **MCP multiplexing** | Expose multiple MCP servers as one endpoint |
| 7 | **Token exchange** | RFC 8693 — validate an inbound Auth0 JWT, swap for a gateway-issued credential via AGW's built-in STS |
| 8 | **Tool filtering with CEL** | Restrict MCP tools per user via JWT claims |
| 9 | **Observability** | Proxy metrics + the enterprise UI |
| 10 | **Waypoint mode** | Run agentgateway as an Istio ambient waypoint, applying east-west authz |

## Prerequisites

- A Kubernetes cluster with **enterprise agentgateway already installed** (`v2026.5.1`), including the management chart, Redis-backed rate limiter, and ClickHouse/UI telemetry stack.
- `kubectl` pointed at that cluster.
- Jupyter with a **bash kernel** ([`bash_kernel`](https://github.com/takluyver/bash_kernel)), since the cells are shell.
- `jq` and `curl` on the machine running the notebook.
- An **Anthropic API key** for section 1's live Anthropic route.
- An **Auth0 tenant** (client-credentials app) for sections 7–8.

### Credentials

The notebook reads two things from the environment:

- `ANTHROPIC_API_KEY` — your Anthropic key.
- Auth0 settings, sourced from `~/.auth0.env` (kept out of this repo):

  ```sh
  export AUTH0_DOMAIN="your-tenant.us.auth0.com"
  export AUTH0_AUDIENCE="https://your-api/"
  export AUTH0_CLIENT_ID="..."
  export AUTH0_CLIENT_SECRET="..."
  ```

  Save it `chmod 600 ~/.auth0.env`. The setup cell does `. ~/.auth0.env` to load it.

## Running it

1. **Bootstrap the demo workloads** (idempotent):

   ```sh
   ./init.sh
   ```

   This deploys the upstreams the notebook points at and the gateway plumbing that isn't itself a teaching moment:

   - `mock-llm` — vLLM-sim, stands in for any OpenAI-compatible model — in the **`ai-models`** namespace
   - `httpbin` and `server-everything` (`@modelcontextprotocol/server-everything`) in the **`mcp-servers`** namespace
   - `sts` / `sts-jwks` `AgentgatewayBackend`s pointing at the in-cluster STS on `:7777`, plus an `HTTPRoute` exposing it at `/sts`

2. **Open `demo.ipynb`** and run the Setup cell first — it runs `init.sh`, sources Auth0 creds, and resolves the gateway address into `$GATEWAY`. Then walk the sections top to bottom.

3. **Tear down** when you're done:

   ```sh
   # Resources the notebook itself created:
   #   run the Cleanup cell at the bottom of demo.ipynb
   ./init.sh down   # removes the init.sh workloads + STS plumbing
   ```

## Files

- `demo.ipynb` — the demo, section by section.
- `init.sh` — pre-demo bootstrap (`./init.sh` to deploy, `./init.sh down` to tear down).
- `~/.auth0.env` — Auth0 credentials, sourced at setup (not in this repo).
