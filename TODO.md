# TODO

## PVC Naming Standard Alignment

CLAUDE.md specifies PVC naming pattern: `<namespace>-<app>-<purpose>-<replica>`

**Current state:** Apps are NOT following this pattern:
- Plex: `config-plex-0` (should be `temple-of-time-plex-config-0`)
- Jellyfin: `config-jellyfin-0` (should be `temple-of-time-jellyfin-config-0`)
- Linkwarden: `linkwarden-data-linkwarden-0` (should be `temple-of-time-linkwarden-data-0`)
- Mealie: `mealie-data-mealie-0` (should be `temple-of-time-mealie-data-0`)

**Action needed:**
- Decide: Update CLAUDE.md to match reality OR migrate all apps to follow the documented standard
- This will require downtime for affected apps (Plex, Jellyfin, Mealie, Linkwarden, etc.)
- Should be done during planned maintenance window
