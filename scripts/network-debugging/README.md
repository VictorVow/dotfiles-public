# Network debugging toolkit

Scripts for diagnosing in-home streaming/LAN problems across the two-node Linksys Velop MX4200 mesh — latency spikes, packet loss, throughput ceilings, and attributing them to the right segment (own radio hop, node↔node backhaul, or the far client's hop). Built during the 2026-07-03 streaming investigation; full findings and topology in `docs/system/home-networking.md`.

All defaults (IPs, SSH targets, interface) live in `net-lib.sh` and can be overridden via environment variables. IPs are DHCP leases — verify against the MACs documented in home-networking.md if results look wrong. The scripts need bash, iproute2, `iw`, `iperf3`, and SSH access to `lord@lord-ubuntu` (wired vantage point) and `chief-win11` (see the SSH setup section of home-networking.md).

## The playbook

Work through these in order; each step either finds the problem or excludes a segment.

1. **`./net-wifi-link.sh`** — this machine's radio. Signal better than −60 dBm with high PHY rate = RF is fine; if you also see high `tx retries` (with 0 failed), suspect airtime contention — which shows up as latency jitter, not loss.
2. **`./net-segment-latency.sh`** — the core isolation test. Pings the near node (own hop), far node (+backhaul), a wired host (+wire, forwarded path), and the desktop end-to-end. The (2)−(1) delta is the backhaul's cost — healthy is +2–5 ms. Jitter present in (1) *and* (3) is real forwarding jitter on your own hop, not node-CPU ICMP slow-pathing. Add `-d` to also measure the desktop's hop from its own side via SSH (the segment that's invisible from here).
3. **`./net-deploy-iperf3.sh`** — one-time per boot of lord-ubuntu: pushes iperf3 + libs to its `/tmp` (no root needed there).
4. **`./net-throughput.sh`** — the full TCP matrix (6 runs, ~1 min). Isolates each radio hop against the wired host and measures end-to-end both directions. The printed baseline (A=156 B=232 C=99 D=130 E=93 F=40 Mbps, 2026-07-03) is the healthy reference: the desktop hop is the expected bottleneck; the backhaul carries ≥232 Mbps and is *not* a suspect.
5. **Under load**: repeat step 2 while an actual stream runs. On 2026-07-03 the laptop hop's tail went 113 → 190 ms under load while the desktop hop stayed at 1/2/4 ms — that asymmetry is what named the jitter culprit.

## Hard-won gotchas

- **The desktop firewalls ICMP** — raw `ping 192.168.x.x` shows 100% loss even when everything is healthy. Use `tailscale ping chief-win11-desktop` (WireGuard) or SSH instead.
- **Windows Public-profile firewall eats inbound iperf3** even with an explicit `New-NetFirewallRule` allow on the port (the WiFi network is categorized Public; Tailscale's interface is Private). Don't fight it: run the desktop as *client*, or test against its tailnet IP.
- **lord-ubuntu's ufw blocks inbound LAN ports but allows `tailscale0`** — so lord is reachable on `100.x.x.x:5201` but not `192.168.x.x:5201`. Run lord as client for raw-TCP tests, or target its tailnet IP.
- **Tailscale SSH on lord-ubuntu requires the username `lord`** — any other user fails with `tailscale: failed to look up local user`. No passwordless sudo there; hence the `/tmp` iperf3 deploy trick.
- **The desktop's inbound SSH shell is cmd.exe** — chain with `&&`, not `;`. And `Start-Process iperf3` doesn't resolve the winget alias; use the full path under `AppData\Local\Microsoft\WinGet\Packages\`.
- **winget PATH updates don't reach the installing shell** — "command not recognized" right after `winget install` just means open a new shell.
- **RF contention is bursty** — a single clean 20 s ping window occurs even on a congested channel (observed: 3.8 ms avg once, ~30 ms avg on the very next identical run). Repeat runs before declaring anything fixed.
- **Don't ping a Velop node's own IP as your only evidence** — node-CPU ICMP handling can mislead in either direction. Always corroborate with a *forwarded* path through the node to a host behind it.
- **lord-ubuntu is dual-homed** (wired .217 + WiFi .222, same subnet). Route metric prefers the wire, but verify with `ip route get <target>` before trusting a "wired" measurement.
- **WiFi power-save is a red herring here** — `iw set power_save off` changed nothing measurable; the jitter is airtime contention. (Checked 2026-07-03; don't re-chase it.)
- **NFS `dd` is not a throughput test** — `iflag=direct` over NFS serializes on RTT and reported 12 MB/s on a path iperf3 proved does 232 Mbps.
