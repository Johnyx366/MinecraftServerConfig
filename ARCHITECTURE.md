# Architecture

`MinecraftServers` holds versioned manifests, properties and human documentation. `MinecraftServerConfig` holds the portable CLI and policy. Runtime lives at `$MC_RUNTIME_ROOT` (macOS default: `~/MinecraftServerRuntime`, deliberately without spaces because the official Chocolate launcher rejects them; Linux: `~/.local/share/minecraft-server-runtime`), one directory per ID. Thus deleting a runtime never alters Git or a backup repository.

Each runtime has `server/` (official extracted files), `world/`, `logs/`, `state/` (PID, local RCON secret, runtime metadata), and `downloads/`. The manifest prevents duplicate inventory IDs/ports and provides memory accounting. A JSON document is valid YAML 1.2, so manifests use JSON syntax without a nonstandard YAML parser.

The portable core is Python 3 standard library. Platform adapters are intentionally small: macOS lifecycle can generate user `launchd` plists; Linux support has the same runtime layout and is ready for a future systemd adapter. No Docker.
