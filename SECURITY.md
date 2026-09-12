# Security and networking

RCON is enabled solely for consistent backups. Its password is randomly generated in the runtime with mode 0600 and never committed. Keep TCP `rcon_port` blocked on every interface: macOS Application Firewall is not a substitute for router policy. Do not forward it.

Minecraft uses one distinct TCP port per server (Chocolate: 25565). LAN clients use the Mac's LAN address. External access requires an intentional router port-forward and, if applicable, a public IP; CGNAT prevents ordinary inbound forwarding. Configure a single specific Minecraft TCP forward, restrict firewall access where possible, retain `online-mode=true`, and use the whitelist. DMZ is a temporary double-NAT workaround, never a substitute for a narrow forwarding rule; it must target the upstream router, never the Mac, and requires WAN administration and UPnP to be disabled. `mc doctor` checks local port conflicts but cannot inspect your router or CGNAT.

Remote restic repositories must use restic encryption/password material supplied by environment or a protected password file, never this repository.
