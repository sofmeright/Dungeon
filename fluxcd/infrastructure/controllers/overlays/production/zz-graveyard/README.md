# Infrastructure Graveyard

This directory contains legacy/superseded infrastructure components that are no longer actively deployed but are preserved for reference.

## Components

### prometheus
- **Superseded by**: Mimir + kube-prometheus-stack
- **Reason**: Standalone Prometheus replaced by Grafana Mimir with Kafka-based ingest storage for improved scalability and long-term metrics storage
- **Moved**: 2025-11-07

### traefik
- **Superseded by**: Istio + Gateway API
- **Reason**: Migration to service mesh architecture with Kubernetes Gateway API for standardized ingress routing
- **Moved**: 2025-11-07

### pihole
- **Superseded by**: AdGuard Home
- **Reason**: AdGuard provides better DNS filtering, HTTPS DNS-over-TLS, and improved UI/management
- **Status**: Was already disabled
- **Moved**: 2025-11-07

## Usage

These components are **NOT deployed** by FluxCD and should not be referenced in active kustomizations. They are kept here as:
- Reference material for configuration patterns
- Historical record of infrastructure evolution
- Examples for future similar deployments

If you need to restore or reference any of these components, review their configuration but consider whether the superseding technology would be more appropriate.
