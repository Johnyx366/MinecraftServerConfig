# Operations

`bootstrap [java]` installs/checks macOS dependencies. `list`, `status [ID|--all]`, `doctor [ID|--all]`, `deploy [ID|--all]`, `start`, `stop`, `restart`, `backup`, `restore ID SNAPSHOT`, and `checkpoint` are implemented. `install` is an alias for `deploy`.

Deploy is idempotent: it never overwrites a nonempty extracted server or a world. A changed pack requires an explicit migration workflow. Start calculates the aggregate configured Xmx of running servers and refuses to exceed 75% of detected RAM. It uses the launch script supplied by the official pack when present; otherwise it stops with an actionable error rather than guessing a Forge command.

For persistence on macOS, `./mc service install ID` generates a user LaunchAgent from the manifest; `service remove ID` unloads/removes it. Only `autostart: true` is accepted for installation. Use `service status ID` to inspect it.
