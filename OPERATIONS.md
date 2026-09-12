# Operations

`bootstrap [java]` installs/checks macOS dependencies. `list`, `status [ID|--all]`, `doctor [ID|--all]`, `deploy [ID|--all]`, `start`, `stop`, `restart`, `backup`, `restore ID SNAPSHOT`, and `checkpoint` are implemented. `install` is an alias for `deploy`.

`idle-pause start ID` checks the local RCON player count every 10 seconds and pauses `doDaylightCycle` while no players are online; it resumes the day/night cycle on the next join. This deliberately does not freeze game ticks, entities, redstone, chunk work, RCON, or networking. Use `idle-pause status ID` and `idle-pause stop ID` to operate it.

Deploy is idempotent: it never overwrites a nonempty extracted server or a world. A changed pack requires an explicit migration workflow. Start calculates the aggregate configured Xmx of running servers and refuses to exceed 75% of detected RAM. It uses the launch script supplied by the official pack when present; otherwise it stops with an actionable error rather than guessing a Forge command.

For Chocolate Edition 1.9.1, keep `Xmx` at or below 8 GiB. Its official 1.9.1 changelog recommends 8 GiB and warns that allocating 10+ GiB can cause problems. Server-side world generation, mobs, redstone, and simulation are already authoritative; clients still necessarily render their own textures and models.

For persistence on macOS, `./mc service install ID` generates a user LaunchAgent from the manifest; `service remove ID` unloads/removes it. Only `autostart: true` is accepted for installation. Use `service status ID` to inspect it.
