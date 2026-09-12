# Networking and double NAT

## Current deployment record

The first deployment uses this verified private LAN path:

```text
Minecraft Mac (Ethernet en10, reserved 192.168.0.28)
  -> TP-Link AXE5400 LAN gateway (192.168.0.1)
  -> AXE5400 WAN / Totalplay LAN
  -> Totalplay router / Internet
```

The AXE5400 DHCP binding list contains `Juans-MBP` mapped to `192.168.0.28`. Do not configure a manual macOS IP in addition to this reservation. If replacing the Mac or changing its active network adapter, update the binding using that adapter's MAC address.

The server has been tested locally: it starts successfully and a whitelisted Forge client can authenticate. Public Internet reachability is **not yet verified**. Do not record public IPs, router passwords, API tokens, RCON passwords, or player UUIDs in Git.

## Double-NAT configuration

Use the following order. The AXE5400 has two different addresses: its LAN gateway (`192.168.0.1`) and a WAN address assigned by Totalplay. Never substitute the Mac's `192.168.0.28` for the AXE5400 WAN address in Totalplay.

1. Reserve the AXE5400's WAN address in Totalplay DHCP. Dynamic assignment can change after a reboot; a DMZ or forwarding rule does not follow it automatically.
2. On the AXE5400, forward **TCP 25565 only** to `192.168.0.28:25565`.
3. Preferred: on Totalplay, forward **TCP 25565 only** to `AXE5400_WAN_IP:25565`.
4. Current temporary alternative: Totalplay DMZ may target `AXE5400_WAN_IP`, then the AXE5400 forwards only TCP 25565 to the Mac. DMZ must never target the Mac directly. Turn off AXE5400 WAN/remote administration and UPnP while DMZ is enabled.
5. Never forward TCP 25575 (RCON), and do not enable a rule for it through UPnP.

Before using a public hostname, validate the route from outside the home network (mobile data or a remote host) with TCP port 25565. A ping tests ICMP, not Minecraft's TCP port, and is not a valid test. A client on the Totalplay LAN should first use `AXE5400_WAN_IP:25565`; an external client uses the current public IP or configured DNS hostname.

If Totalplay's WAN address is private (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) or shared-CGNAT (`100.64.0.0/10`), request a public IPv4 address or use a private overlay such as Tailscale instead of public forwarding.

## Public hostname / DDNS

DNS gives the dynamic public IP a stable name; it is not a firewall or tunnel. Once external TCP testing succeeds, use a domain such as `mc.example.com` with a DNS-only A record. Do not enable Cloudflare's standard HTTP proxy for Minecraft TCP traffic. A Cloudflare updater on the Mac should use an API token limited to that zone's DNS edit permission and keep the token outside Git. See [Cloudflare DNS record API](https://developers.cloudflare.com/api/resources/dns/subresources/records/methods/edit/).

Before sharing a public hostname, create and verify a restic backup, retain `online-mode=true` and the whitelist, and review operator access.
