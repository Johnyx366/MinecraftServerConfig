# Migration

On the destination, clone both repositories as siblings, run `./mc bootstrap`, copy or configure restic credentials securely, run `./mc doctor --all`, then restore each documented snapshot. Deploy the exact manifest first, then restore the matching world; do not let a newer pack touch it.

For an upgrade: branch `migration/...`, capture and verify backups, record snapshot IDs and current commits, copy the runtime for testing, change only pinned manifest data, deploy/test, and only then merge/tag. Roll back by redeploying the old commit and restoring its snapshot. Validate startup, mod/loader versions, world load, player join, and a fresh backup.
