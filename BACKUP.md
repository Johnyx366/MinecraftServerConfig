# Backups and restore

Backups use restic for deduplication, compression, authenticated encrypted repositories and verification. Configure outside Git:

```sh
export MC_RESTIC_REPOSITORY='sftp:user@host:/path' # or a local path for testing
export RESTIC_PASSWORD_FILE="$HOME/.config/minecraft/restic-password"
restic init
```

`./mc backup ID` uses local RCON while running: `save-off`, `save-all flush`, restic snapshot, then `save-on` even on failure. If RCON is unavailable it refuses to snapshot an active server; stopped servers are safe. It tags snapshots with server ID and current config commit. `./mc checkpoint` backs up every server and writes a timestamped JSON mapping under `checkpoints/` (commit this metadata deliberately if it is a meaningful checkpoint).

For restore: stop the server, run `./mc restore ID SNAPSHOT`, inspect the newly saved old world under `world.before-restore-*`, then start and validate. Restoration never deletes the previous world.
