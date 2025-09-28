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

*Add additional infrastructure tasks here as they come up*