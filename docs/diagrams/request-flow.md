# Request Flow Diagram

This Mermaid diagram renders automatically on GitHub. It shows the path of a single request through the Istio mesh to cart-service.

```mermaid
flowchart TD
    A[External Client] --> B[Istio Gateway]
    B -->|TLS termination| C[VirtualService / HTTPRoute]
    C -->|host + path + header matching| D[RequestAuthentication]
    D -->|validates JWT if present| E[PeerAuthentication]
    E -->|enforces mTLS| F[AuthorizationPolicy]
    F -->|CUSTOM → DENY → ALLOW| G[DestinationRule]
    G -->|load balancing, circuit breaking, connection pools| H[cart-service pod]
    H --> I[Telemetry]
    I -->|metrics, traces, access logs| J[Observability Backend]

    style A fill:#e1f5fe
    style B fill:#fff3e0
    style C fill:#fff3e0
    style D fill:#fce4ec
    style E fill:#fce4ec
    style F fill:#fce4ec
    style G fill:#e8f5e9
    style H fill:#f3e5f5
    style I fill:#fffde7
    style J fill:#fffde7
```

## Egress flow (controlled outbound)

```mermaid
flowchart LR
    A[cart-service sidecar] --> B[Egress Gateway]
    B --> C[External API - api.stripe.com]

    subgraph mesh [Istio Mesh]
        A
        B
    end

    style A fill:#f3e5f5
    style B fill:#fff3e0
    style C fill:#e1f5fe
```

## Policy evaluation order

```mermaid
flowchart TD
    A[Request arrives] --> B{CUSTOM policy exists?}
    B -->|yes| C[Delegate to external provider]
    B -->|no| D{Any DENY policy matches?}
    C --> D
    D -->|yes| E[❌ Request denied]
    D -->|no| F{Any ALLOW policy exists for workload?}
    F -->|no| G[✅ Request allowed - no policy means open]
    F -->|yes| H{Request matches an ALLOW rule?}
    H -->|yes| I[✅ Request allowed]
    H -->|no| J[❌ Request denied]

    style E fill:#ffcdd2
    style J fill:#ffcdd2
    style G fill:#c8e6c9
    style I fill:#c8e6c9
```
