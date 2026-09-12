# Deliberate pending improvements

These are planned, not silently enabled.

1. **External validation and DDNS.** Test TCP 25565 from mobile data first. If it works, configure a DNS-only DDNS record. Do not use Cloudflare's HTTP proxy for Minecraft.
2. **Reduce the temporary DMZ exposure.** Reserve the TP-Link WAN address in Totalplay and replace DMZ with a narrow TCP 25565 forwarding rule. Keep TP-Link remote administration and UPnP disabled.
3. **Encrypted offsite restic copy.** Add and test an independent remote repository before treating local disk backups as sufficient disaster recovery.
4. **Optional richer player telemetry.** Per-player ping/playtime cannot be obtained truthfully through vanilla/Forge RCON. Evaluate a pinned, compatible server-side mod only if that information becomes worth its maintenance burden.

Do not treat a pending item as permission to alter router security, expose services, add credentials, or install mods automatically.
