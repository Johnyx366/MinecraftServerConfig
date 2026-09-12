# Instructions for agents

This repository is the operational source of truth; its sibling `../MinecraftServers` is the declarative source of truth for instances. Read `README.md`, `ARCHITECTURE.md`, the target manifest, and `git status` in both repositories before changing anything. Use `./mc doctor --all` before and after operational work.

Platform is detected by `./mc doctor`; supported identifiers are `darwin-arm64`, `linux-arm64`, and `linux-x86_64`. Minecraft runs natively, never in Docker. Runtime defaults outside both Git repositories and can be redirected only with `MC_RUNTIME_ROOT`.

Never: delete a world without a verified snapshot; upgrade Minecraft/loaders/mods automatically; casually change world-generation mods; expose RCON publicly; commit credentials or restic repositories; overwrite configuration without inspecting the diff; perform destructive migration without a recoverable checkpoint. Before destructive work: determine state, make a consistent snapshot, verify it, record its ID, then proceed.

Use official server packs, pin exact artifacts and hashes, and preserve unknown existing runtime files until reviewed. Read `NETWORKING.md` before changing LAN, DHCP, NAT, port forwarding, DMZ, DDNS, or firewall settings. `main` contains every server; branches are `feat/`, `fix/`, `migration/`, or `test/`. Checkpoints are Git tags named `checkpoint/YYYY-MM-DD[-label]` plus restic snapshot metadata. Router/NAT changes, remote-backup credentials, and accepting the Minecraft EULA are human-authorized actions, never automatic.
