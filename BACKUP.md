# Backups and restore

Backups use restic for deduplication, compression, authenticated encrypted repositories and verification. Configure outside Git:

```sh
export MC_RESTIC_REPOSITORY='sftp:user@host:/path' # or a local path for testing
export RESTIC_PASSWORD_FILE="$HOME/.config/minecraft/restic-password"
restic init
```

`./mc backup ID` uses local RCON while running: `save-off`, `save-all flush`, restic snapshot, then `save-on` even on failure. If RCON is unavailable it refuses to snapshot an active server; stopped servers are safe. It tags snapshots with server ID and current config commit. `./mc checkpoint` backs up every server and writes a timestamped JSON mapping under `checkpoints/` (commit this metadata deliberately if it is a meaningful checkpoint).

## Initial local recovery point

The initial setup created an encrypted local restic repository at `~/MinecraftBackups/restic-repository`; its password file is `~/MinecraftBackups/restic-password` with mode 0600. This is a recoverable local checkpoint, not protection against loss of the Mac. Add an encrypted remote restic target before relying on it as the sole backup.

Before the first intentional world reset, snapshot `54f48efb` was created and verified. The freshly generated seeded world was then captured and verified as snapshot `0ef18554`. The old world directory remains as `world.before-reset-20260912T214448Z` until an independently stored backup strategy has been verified.

For restore: stop the server, run `./mc restore ID SNAPSHOT`, inspect the newly saved old world under `world.before-restore-*`, then start and validate. Restoration never deletes the previous world.
