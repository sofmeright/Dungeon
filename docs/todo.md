# Infrastructure TODO List

## Backup and Disaster Recovery

### Velero Backup Setup
- [ ] Deploy MinIO on NAS with flash storage + ZFS pool
- [ ] Configure MinIO S3-compatible API endpoint
- [ ] Deploy Velero server in Kubernetes cluster
- [ ] Configure Velero to use MinIO as backup storage backend
- [ ] Set up Ceph CSI volume snapshot support for RBD volumes
- [ ] Create backup schedules:
  - [ ] Daily: Application configs and secrets
  - [ ] Weekly: Full cluster backup including volumes
  - [ ] Monthly: Long-term retention backups
- [ ] Test backup and restore procedures
- [ ] Document backup/restore processes

**Notes:**
- Ceph RBD volumes (`plex-config`, `plex-transcode`) can be snapshotted via Velero
- SMB/CIFS volumes are external shares - backup at SMB server level (`gringotts`)
- ZFS on NAS provides additional benefits: compression, dedup, local snapshots

## Future Infrastructure Items

### Gateway Access Tiering
Reorganize gateways from domain-based to access-level separation:

**Target Architecture:**
- **Cell-membrane (public)** - No auth, world-accessible
  - Landing pages, public sites
  - Public APIs, webhooks
  - Marketing sites
- **Phloem (privileged)** - Requires auth/SSO
  - Personal dashboards, productivity apps
  - Business apps behind SSO
  - Media servers (Plex, Jellyfin, Nextcloud)
- **Xylem (internal)** - Network-restricted
  - Admin panels (*arr stack, NVR)
  - Infrastructure tools
  - Sensitive configs

**Benefits:**
- Different rate limits per tier
- SSO enforcement on phloem (Zitadel/OAuth2 proxy)
- IP allowlisting on xylem
- Different WAF rules per exposure level

**Migration Tasks:**
- [ ] Audit all HTTPRoutes and categorize by access level
- [ ] Plan certificate changes (which domains on which gateway)
- [ ] Update fairer-pages HTTPRoutes for new structure
- [ ] Implement SSO requirement on phloem gateway
- [ ] Implement IP allowlisting on xylem gateway
- [ ] Migrate services incrementally by tier
- [ ] Update DNS as needed
- [ ] Document new access model

*Add additional infrastructure tasks here as they come up*