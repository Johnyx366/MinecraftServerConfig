# Current deployment record

This is the human-readable record of the first real deployment. It contains no public IP, password, token, player UUID, or router credential.

## Host and runtime

- Host: Apple Silicon M1 Max, 32 GiB unified memory, macOS (`darwin-arm64`).
- Minecraft runs natively with Homebrew OpenJDK 17 ARM64; Docker is not used.
- Runtime root: `~/MinecraftServerRuntime`. This path intentionally contains no spaces because Chocolate Edition's supplied launcher rejects them.
- Native operator app: `~/Applications/Minecraft Server Control.app`. Regenerate after moving either repository with `./mc app install chocolate-edition`.

## Chocolate Edition

- Pack: Chocolate Edition 1.9.1; Minecraft 1.19.2; Forge 43.5.0; Java 17.
- Pack SHA-256: `74b712246cfebc0c5cb6316dadfe0ef13703161f221aaa7405396d1041b44b5f`.
- Memory policy: Xms 4 GiB, Xmx 8 GiB. Do not raise this automatically.
- Current new-world seed: `-3691007458655063350`.
- RCON is loopback-only in operational use and must never be forwarded.

## Backups and recovery

- Local encrypted restic repository: `~/MinecraftBackups/restic-repository`.
- Password file: `~/MinecraftBackups/restic-password`, mode 0600; neither content nor path belongs in Git configuration.
- GUI/CLI local references: `~/.config/minecraft-server-control/restic.env`, mode 0600; it stores only paths, not the password.
- Reset safety points: `54f48efb` (pre-reset world) and `0ef18554` (new seeded world), both verified when created.
- The pre-reset world remains retained under `world.before-reset-20260912T214448Z` until independent offsite recovery is verified.

## LAN and routing

- Mac private LAN address: `192.168.0.28`, reserved through the TP-Link AXE5400 IP/MAC binding for `Juans-MBP`.
- The Mac must use DHCP; do not also configure a manual macOS address.
- Topology is Mac -> TP-Link AXE5400 -> Totalplay (double NAT).
- TP-Link forwards TCP 25565 to the Mac. Totalplay must target the TP-Link's reserved WAN address, never the Mac.
- A Totalplay DMZ pointing at that WAN address is temporary; no DMZ or forwarding may expose TCP 25575.
- Public Internet reachability still requires a test from outside the home network. See `NETWORKING.md`.

## Change protocol

Before changing pack, mods, seed/world generation, router rules, runtime root, or backups: make and verify a restic snapshot, record its ID, inspect the Git diff, then make the change. Update this file when a documented deployment decision changes.
