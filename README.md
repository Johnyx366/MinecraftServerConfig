# MinecraftServerConfig

Reproducible native Minecraft infrastructure. It operates the sibling `MinecraftServers` checkout and keeps all mutable state outside Git.

On macOS, runtime defaults to `~/MinecraftServerRuntime`; this path intentionally has no spaces because the official Chocolate Edition launcher refuses paths containing them.

```sh
./mc bootstrap
./mc doctor --all
./mc deploy chocolate-edition
./mc start chocolate-edition
```

On macOS ARM64, install Homebrew once if absent, then bootstrap installs native OpenJDK 17 and restic. The first Chocolate deployment requires the official server-pack ZIP and its reviewed SHA-256; see its README. Set `MC_RESTIC_REPOSITORY` and `RESTIC_PASSWORD_FILE` outside Git before backups.

Read [architecture](ARCHITECTURE.md), [operations](OPERATIONS.md), [backups](BACKUP.md), [security](SECURITY.md), [networking](NETWORKING.md), [current deployment](CURRENT_DEPLOYMENT.md), [pending improvements](PENDING.md), and [migration](MIGRATION.md). `./mc help` is the command reference.
