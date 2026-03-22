# Cilium Network Policy Spec

Canonical reference for the cluster's Cilium L3/L4 policy architecture.
When reality diverges from this spec, fix reality — not the spec.

## Trust Model

- `enableDefaultDeny: {ingress: false, egress: false}` on all CNPs — individual CNPs are additive and do not implicitly enable enforcement on unrelated pods. However, Cilium activates enforcement **per direction**: ingress enforcement is triggered when a pod is selected by a rule with an `ingress` section, and egress enforcement is triggered when selected by a rule with an `egress` section. A CCNP with an egress rule matching all pods (like `allow-dns-egress`) enables egress enforcement globally.
- **Target state:** migrate to `enableDefaultDeny: {ingress: true}` on CNPs, eliminating the separate `default-deny-ingress.yaml` files. Requires all pods to have complete ingress rules before flipping.
- `default-deny-ingress.yaml` per namespace — explicit ingress deny via empty `ingress: []`
- Egress: CCNP `allow-dns-egress` matches all pods, which enables egress enforcement cluster-wide. Once active, pods can ONLY egress to explicitly allowed destinations. Pods needing external egress (e.g., zigbee2mqtt → SLZB-06) must have explicit `toCIDR` egress rules.

## Policy Categories

### 1. LAN LoadBalancer Access (per service)

**Pattern:** `fromCIDRSet` with RFC1918, anti-hairpin exclusion

```yaml
fromCIDRSet:
  - cidr: "10.0.0.0/8"
  - cidr: "172.16.0.0/12"
  - cidr: "192.168.0.0/16"
    except:
      - "192.168.144.0/20"   # pod CIDR — prevent identity bypass via LB IP
```

- pfSense owns LAN segment access control — Cilium does not duplicate it
- Pod CIDR exclusion is required **only on ranges that actually overlap pod addressing**: `192.168.0.0/16` contains `192.168.144.0/20`, so it gets the `except` block
- `172.16.0.0/12` has no exclusion because `192.168.144.0/20` is not within that range — do not cargo-cult exceptions onto unrelated CIDRs

### 2. CCNP Contracts (cluster-wide)

**Path:** `fluxcd/infrastructure/configs/base/cilium-policies/`

| Contract | Gate | Purpose |
|---|---|---|
| `contract-postgres` | `cap.postgres` + `access-scope-postgres` | PostgreSQL access |
| `contract-redis` | `cap.redis` + `access-scope-redis` | Redis access |
| `contract-mariadb` | `cap.mariadb` + `access-scope-mariadb` | MariaDB access |
| `contract-ingress-backend` | `ingress: "true"` | Gateway → backend (generated) |
| `allow-dns-egress` | all pods | DNS egress (enables egress enforcement) |

### 3. Inter-Component (per app)

- `fromEndpoints` with app/component labels
- Port-scoped
- Example: `allow-harbor-nginx-to-core`

### 4. Cross-Namespace Monitoring

- Gatus: `fromEndpoints` with `app.kubernetes.io/name: gatus` + namespace label
- Uptime-kuma: same pattern

## Capability Label Convention

| Label | Where | Meaning |
|---|---|---|
| `cap.<service>: "true"` | client pod | May access this service type |
| `access-scope-<service>: <ns>.<app>.<svc>` | client pod | Which instance it may access |
| `access-class: <service>` | server pod | Server provides this service type |
| `service-scope: <ns>.<app>.<svc>` | server pod | Globally unique instance identity |

**Evaluation:**
- Client has matching `cap.<service>: "true"`
- Client `access-scope-<service>` value equals server `service-scope` value
- Server `access-class` equals the requested service type

## Infrastructure Labels

| Label | Meaning |
|---|---|
| `policy.prplanit.com/ingress: "true"` | Receives gateway traffic |
| `policy.prplanit.com/probe: "true"` | Accepts health check probes |
| `policy.prplanit.com/metrics: "true"` | Exposes Prometheus metrics |

## Hardening Principles

1. **Defense in depth with Istio.** Cilium is the packet-path containment layer (L3/L4). Istio is the workload-identity authorization layer (L7). Neither should assume the other caught everything. Both layers must independently prevent unauthorized access.

2. **Egress classification model.** Every workload falls into one of these classes:
   - **No egress** — default when `allow-dns-egress` is the only matching rule
   - **Cluster-internal only** — explicit `toEndpoints` rules
   - **DNS only** — the baseline (covered by `allow-dns-egress`)
   - **Specific RFC1918 device egress** — explicit `toCIDR` with port scope (e.g., zigbee2mqtt → SLZB-06)
   - **Specific internet egress** — explicit `toFQDNs` or `toCIDR` with port scope (e.g., adguard → upstream DNS)
   - Keep egress grants as narrow as operationally necessary. Over-broad egress is the primary post-compromise weaponization surface.

3. **One app role = one SA.** Cilium label-based contracts assume workload identity boundaries are granular. If multiple unrelated pods share labels, contracts become coarser than intended.

## Anti-Patterns

- **Never express negative identity matching** in Cilium L3/L4 policy — use CIDR scoping and label-based contracts instead
- **Never exclude `172.22.144.0/24`** (node subnet) from `fromCIDRSet` — pfSense owns LAN access control, and legitimate LAN hosts share that subnet
- **Never use sed/string replacement** on policy files — use Edit tool with full context
- **Never create one-off policies** when a capability label + existing CCNP contract would work

## When to Revise Policy vs App

1. Pod denied access it legitimately needs → **check labels first**
2. Labels present but still denied → **check CCNP contract port list**
3. External egress blocked → **add explicit egress rule (toCIDR + toPorts)**
4. No existing pattern fits → **update this spec first, then implement**
