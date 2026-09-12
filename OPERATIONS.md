# Operations

`bootstrap [java]` installs/checks macOS dependencies. `list`, `status [ID|--all]`, `doctor [ID|--all]`, `deploy [ID|--all]`, `start`, `stop`, `restart`, `backup`, `restore ID SNAPSHOT`, and `checkpoint` are implemented. `install` is an alias for `deploy`.

`./mc dashboard chocolate-edition` shows a compact terminal control panel. It is dark-theme-friendly and uses vivid ANSI colours in macOS Terminal, iTerm2, and the VS Code terminal; set `NO_COLOR=1` for plain text. It does not change the system font or background: choose those in the terminal profile.

`./mc toggle chocolate-edition` is the normal human power switch. When off, it starts the pack and waits (up to three minutes) for the current launch to emit Minecraft's ready message. When on, it sends the normal graceful termination signal and waits up to 30 seconds; it never force-kills a process. `./mc wait-ready chocolate-edition` is available for scripts after `start`.

On macOS, `./mc app install chocolate-edition` builds and opens **Minecraft Server Control.app** in `~/Applications`. It is a native SwiftUI panel with the Creeper icon, live state, recent colour-coded console output, refresh, the same safe power switch, a command input, and player list. Player names come from loopback-only RCON; the displayed millisecond value is local RCON round-trip latency (server health), not invented per-player ping. Player heads are fetched only while needed from `mc-heads.net`, which receives the displayed player name; if offline or unavailable, the app shows a local placeholder. The app contains no credentials; it calls this checkout's `./mc`, so keep the repositories at their configured paths or run `./mc app install chocolate-edition` again after moving them. Building needs the installed Apple Swift toolchain (Xcode Command Line Tools are sufficient).

`idle-pause start ID` checks the local RCON player count every 10 seconds and pauses `doDaylightCycle` while no players are online; it resumes the day/night cycle on the next join. This deliberately does not freeze game ticks, entities, redstone, chunk work, RCON, or networking. Use `idle-pause status ID` and `idle-pause stop ID` to operate it.

Deploy is idempotent: it never overwrites a nonempty extracted server or a world. A changed pack requires an explicit migration workflow. Start calculates the aggregate configured Xmx of running servers and refuses to exceed 75% of detected RAM. It uses the launch script supplied by the official pack when present; otherwise it stops with an actionable error rather than guessing a Forge command.

For Chocolate Edition 1.9.1, keep `Xmx` at or below 8 GiB. Its official 1.9.1 changelog recommends 8 GiB and warns that allocating 10+ GiB can cause problems. Server-side world generation, mobs, redstone, and simulation are already authoritative; clients still necessarily render their own textures and models.

For persistence on macOS, `./mc service install ID` generates a user LaunchAgent from the manifest; `service remove ID` unloads/removes it. Only `autostart: true` is accepted for installation. Use `service status ID` to inspect it.
