# Istio Service Mesh — Teaching Reference

## What is Istio?

Istio is a service mesh that sits between your application services and the network. It intercepts all traffic using sidecar proxies (Envoy) injected alongside each workload.

The two key layers:

- **Control plane** (`istiod`): Manages configuration, issues certificates, and pushes proxy config to all sidecars.
- **Data plane** (Envoy sidecars): Handles the actual traffic — routing, load balancing, mTLS, observability — transparently without application changes.

Everything in this repo is configuration that tells the control plane what behavior to push to the data plane.

---

## Repo structure

```
.
├── README.md
├── core/                          # The resources you'll use in every project
│   ├── gateway.yaml               # HTTP ingress listener
│   ├── https-gateway.yaml         # HTTPS ingress with TLS termination
│   ├── virtual-service-external.yaml   # Routes external traffic from gateway to service
│   ├── virtual-service-internal.yaml   # Internal routing: canary, retries, timeouts
│   ├── destination-rule.yaml      # Load balancing, connection pools, circuit breaking
│   ├── peer-authentication.yaml   # Workload mTLS requirements
│   ├── request-authentication.yaml    # JWT validation
│   ├── authorization-policy.yaml  # Allow/deny/RBAC access control
│   ├── namespace-default-deny.yaml    # Namespace-wide zero-trust baseline
│   └── external-auth-policy.yaml  # Delegate auth to external provider
│
├── observability/                 # Metrics, logs, and traces
│   └── telemetry.yaml            # Access logs, tracing, and metrics config
│
├── egress/                        # Controlling outbound traffic
│   ├── service-entry.yaml         # Register external API (Stripe) in the mesh
│   └── egress-gateway.yaml        # Force outbound traffic through egress gateway
│
├── advanced/                      # Use when core APIs can't solve the problem
│   ├── sidecar.yaml               # Limit proxy config scope and reachability
│   ├── proxy-config.yaml          # Proxy-level tuning (concurrency, image)
│   ├── envoy-filter.yaml          # Low-level Envoy customization (Lua filter)
│   ├── wasm-plugin.yaml           # Custom WebAssembly proxy extension
│   └── rate-limiting.yaml         # Local and global rate limiting
│
├── chaos/                         # Testing and validation
│   ├── fault-injection.yaml       # Chaos testing with delays and aborts
│   └── traffic-mirroring.yaml     # Shadow traffic to a new version
│
├── vm/                            # Non-Kubernetes workloads
│   ├── workload-entry.yaml        # Register an individual VM in the mesh
│   └── workload-group.yaml        # Template for groups of VM workloads
│
└── future/                        # Where Istio is heading
    └── kubernetes-gateway-api.yaml    # Gateway API (Gateway, HTTPRoute, GRPCRoute)
```

---

## Request flow through the mesh

> See [`docs/diagrams/request-flow.md`](docs/diagrams/request-flow.md) for rendered Mermaid diagrams of these flows.

For one request to cart-service, the evaluation order is:

```
External client
      │
      ▼
Istio Gateway
Opens ports and terminates external TLS
      │
      ▼
VirtualService (or HTTPRoute)
Matches host/path/header, selects destination/subset
      │
      ▼
RequestAuthentication
Validates JWT when one is presented (does NOT require a token by itself)
      │
      ▼
PeerAuthentication
Requires workload-to-workload mTLS
      │
      ▼
AuthorizationPolicy
Decides whether the caller/request is permitted
      │
      ▼
DestinationRule
Applies load balancing, connection pools, outlier detection, client TLS
      │
      ▼
cart-service (Envoy sidecar → application container)
      │
      ▼
Telemetry
Produces metrics, access logs, and distributed traces
```

### Policy evaluation order

Authorization policies are evaluated in this order:

1. **CUSTOM** policies (delegated to external provider) — evaluated first
2. **DENY** policies — if any DENY rule matches, the request is rejected
3. **ALLOW** policies — if any ALLOW policy exists for the workload, the request must match at least one ALLOW rule

Important subtleties:
- `RequestAuthentication` alone does NOT reject requests without a token. It only rejects *invalid* tokens. Pair it with an `AuthorizationPolicy` requiring `requestPrincipals` to make JWT mandatory.
- `PeerAuthentication` controls what the *receiving* side accepts. The *sending* side's TLS behavior is controlled by `DestinationRule`.

---

## Recommended production set for your project

For a cart-service, a realistic starting point:

```
cart-service/
├── deployment.yaml
├── service.yaml
├── service-account.yaml
├── destination-rule.yaml
├── virtual-service-internal.yaml
├── virtual-service-external.yaml
├── gateway.yaml
├── peer-authentication.yaml
├── authorization-policy-default-deny.yaml      # namespace-wide
├── authorization-policy-allow-frontend.yaml
├── request-authentication.yaml
├── authorization-policy-require-jwt.yaml
├── telemetry.yaml
└── service-entry-stripe.yaml
```

Add these only when there is a concrete requirement:

```
advanced/
├── sidecar.yaml
├── proxy-config.yaml
├── envoy-filter.yaml
├── wasm-plugin.yaml
├── rate-limiting.yaml
├── fault-injection.yaml          # dev/staging only
├── traffic-mirroring.yaml        # during rollouts
├── egress-gateway.yaml           # compliance/audit
├── workload-entry.yaml           # VM workloads
└── workload-group.yaml           # VM workloads
```

---

## Resource reference

| Resource | Main responsibility |
|---|---|
| Gateway | Exposes ingress or egress listeners |
| VirtualService | Routes and transforms traffic |
| DestinationRule | Applies policies after destination selection |
| PeerAuthentication | Enforces inbound workload mTLS |
| RequestAuthentication | Validates JWT credentials |
| AuthorizationPolicy | Allows or denies access |
| ServiceEntry | Registers external or non-Kubernetes services |
| Sidecar | Limits proxy configuration and service visibility |
| Telemetry | Configures metrics, access logs, and tracing |
| ProxyConfig | Adjusts workload proxy settings |
| EnvoyFilter | Performs low-level Envoy customization |
| WasmPlugin | Adds custom WebAssembly proxy logic |
| WorkloadEntry | Represents an individual VM workload |
| WorkloadGroup | Templates groups of VM workloads |

---

## The Kubernetes Gateway API direction

Istio is actively migrating to the [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) as its primary traffic management interface. What this means:

- Classic Istio `Gateway` + `VirtualService` will continue to work but may not get new features.
- New projects should consider starting with `Gateway` (gateway.networking.k8s.io) + `HTTPRoute`.
- Security CRDs (`PeerAuthentication`, `AuthorizationPolicy`, `RequestAuthentication`) remain Istio-specific and are still required.
- `DestinationRule` capabilities (circuit breaking, connection pools) do not yet have Gateway API equivalents.
- See `future/kubernetes-gateway-api.yaml` in this repo for working examples.

---

## The strongest realistic baseline

1. **Mesh-wide strict mTLS** — `PeerAuthentication` in `istio-system`
2. **Namespace default-deny** — Empty `AuthorizationPolicy` without a selector
3. **Explicit caller allowlists** — Per-workload `AuthorizationPolicy` with `ALLOW`
4. **JWT validation where user identity matters** — `RequestAuthentication` + `AuthorizationPolicy` requiring `requestPrincipals`
5. **Controlled egress** — `ServiceEntry` + `Sidecar` scope (+ egress gateway for compliance)
6. **Telemetry** — Metrics, access logs, and tracing configured per workload

That combination gives you considerably more than a pile of impressive CRDs quietly doing nothing because their selectors do not match.

---

## Debugging and observability commands

Essential `istioctl` commands for troubleshooting:

```bash
# Check mesh-wide configuration issues
istioctl analyze

# Check if sidecars are injected and synced
istioctl proxy-status

# View the routes Envoy has for a specific pod
istioctl proxy-config routes <pod-name> -n shopk8s

# View clusters (upstream services) known to a pod
istioctl proxy-config clusters <pod-name> -n shopk8s

# View listeners on a pod's sidecar
istioctl proxy-config listeners <pod-name> -n shopk8s

# View the full Envoy config dump (verbose)
istioctl proxy-config all <pod-name> -n shopk8s -o json

# Check what authorization policies apply to a workload
istioctl x authz check <pod-name> -n shopk8s

# Verify mTLS status between two workloads
istioctl x describe pod <pod-name> -n shopk8s

# View access logs in real time
kubectl logs <pod-name> -c istio-proxy -n shopk8s -f

# Check if a workload can reach an external service
istioctl x describe svc <service-name> -n shopk8s
```

Common patterns:
- **503 errors** → Check `DestinationRule` TLS mode matches `PeerAuthentication`, check outlier detection is not ejecting all endpoints
- **Connection refused** → Verify `AuthorizationPolicy` allows the caller, check `Sidecar` scope includes the target
- **Timeouts** → Compare `VirtualService` timeout with actual response times, check `connectionPool` limits
- **No metrics/traces** → Verify `Telemetry` resource selector matches the workload labels
- **JWT rejected** → Confirm `jwksUri` is reachable, audiences match, token is not expired

---

## Learning order

If you are new to Istio, read the files in this order:

1. `core/gateway.yaml` / `core/https-gateway.yaml` — How traffic enters
2. `core/virtual-service-external.yaml` — How it gets routed to a service
3. `core/peer-authentication.yaml` — mTLS basics
4. `core/authorization-policy.yaml` — Access control
5. `core/request-authentication.yaml` — JWT validation
6. `core/namespace-default-deny.yaml` — Zero-trust baseline
7. `core/destination-rule.yaml` — Resilience patterns
8. `core/virtual-service-internal.yaml` — Advanced routing
9. `egress/service-entry.yaml` — Egress control
10. `observability/telemetry.yaml` — Observability
11. `future/kubernetes-gateway-api.yaml` — Where Istio is heading next

The folders `advanced/`, `chaos/`, `egress/`, and `vm/` are useful when you hit specific requirements that the core APIs cannot solve.
