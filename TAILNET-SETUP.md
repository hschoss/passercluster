# Tailnet setup — handoff for the next session

Written 2026-10-23, mid-session, after we broke corvus's tailnet reachability
and the user is remote (can't recover). This file is a cold-start briefing for
a future Claude session.

## Why this exists

The goal is to let **passer** (home LAN, `192.168.178.2`) reach the
**corvus-datahub** server (Corvus LAN, `192.168.179.0/24`) so a periodic
fetch/mirror workflow can run on passer. The data server is physically the
same Raspberry Pi as **corvus** (`192.168.179.2`). Call it "corvus" or
"corvus-datahub" — same box.

Threat model (from an earlier architecture discussion in-session, keep this
in mind): IoT/Corvus side could be compromised. The Corvus LAN must not
pivot into trusted LAN. Prefer least-privilege, per-host identity,
one-direction flow where possible.

## Who's who

| Host | Role | Key addresses |
|--|--|--|
| **aquila** | VPS, runs **both** headscale instances in docker + caddy TLS termination | `159.195.124.28`, ssh alias `aquila` user `hannes`, passwordless sudo ✓ |
| **corvus** (= "corvus-datahub") | RPi, Debian 13 trixie, on Corvus LAN | `192.168.179.2`, ssh alias `corvus-ts` user `vault`, sudo requires password |
| **passer** | RPi, Debian 13 trixie, on home LAN | `192.168.178.2`, ssh alias `passer-ts` user `vault`, sudo requires password |
| **schlaeptop** | user's workstation (Arch) | varies, ssh config has user `hannes` |

Two **isolated** tailnets, both self-hosted via headscale on aquila:

| Tailnet | Control URL | Base domain (MagicDNS) | Nodes |
|--|--|--|--|
| **corvus tailnet** | `https://corvus.schloschi.com` (served by `headscale-corvus` container) | `ts.corvus.schloschi.com` ✓ (fixed this session; was `tail.schloschi.com`) | `corvus=100.64.0.1`, `schlaeptop=100.64.0.4` |
| **passer tailnet** | `https://passer.schloschi.com` (served by `headscale-passer` container) | `ts.passer.schloschi.com` | `localhost(iOS)=100.64.0.1`, `passer=100.64.0.2` (fixed this session; was `.1`), `schlaeptop=100.64.0.7` (offline) |

User explicitly wants these two tailnets kept isolated. Each has its own
users table, own preauth keys, own ACLs. No bridging at the headscale level.

aquila layout (relevant paths):

```
/etc/aquila/
├── docker-compose.yml           # both headscales, caddy, tal, vaultwarden
├── headscale/config.yaml        # headscale-corvus config
├── headscale-passer/config.yaml # headscale-passer config
├── caddy/Caddyfile              # TLS reverse proxy
```

headscale version is `0.23.0` (both instances). sqlite backend. Volumes:

```
/var/lib/docker/volumes/aquila_headscale_data/_data/           # corvus side
/var/lib/docker/volumes/aquila_headscale_passer_data/_data/    # passer side
```

Preauth key creation (as of this version):

```bash
sudo docker exec -it headscale-corvus headscale preauthkeys create --user hannes --expiration 1h
sudo docker exec -it headscale-passer headscale preauthkeys create --user hannes --expiration 1h
```

## What's done ✓

1. **Dead WG on passer removed.** `wg-quick@wg0` disabled, `/etc/wireguard/wg0.conf` deleted, local plaintext copy shredded. Confirmed with user. The earlier `~/wg_config.conf` approach failed because passer has no global IPv6 (home FritzBox does not advertise GUA on `192.168.178.0/24`), and the Corvus FritzBox endpoint is only reachable via IPv6.
2. **SSH config fixed to use MagicDNS names, not raw tailnet IPs.** `~/.ssh/config` entries:
   - `corvus-ts: HostName corvus.ts.corvus.schloschi.com`
   - `passer-ts: HostName passer.ts.passer.schloschi.com`
   - stale `100.64.0.1` pins purged from `~/.ssh/known_hosts`. Keys pinned under MagicDNS names.
3. **Base domain renamed on headscale-corvus.** `tail.schloschi.com` → `ts.corvus.schloschi.com`. Edit at `/etc/aquila/headscale/config.yaml` line 51. Backup: `/etc/aquila/headscale/config.yaml.bak-*`.
4. **IP swap on headscale-passer.** `passer` moved from `.1` to `.2`; `localhost` (iOS) moved from `.2` to `.1`. Done via SQLite UPDATE while container stopped. Backup: `/var/lib/docker/volumes/aquila_headscale_passer_data/_data/db.sqlite.bak-20261023T071011Z`.
5. **compose file for second tailscaled** written on corvus at `~/docker-services/tailscale-passer/compose.yml`. It registered successfully once (`100.64.0.3`, hostname `corvus`), route `192.168.179.0/24` **was approved on headscale-passer** (route id 3, enabled=true), but then broke things.

## What's broken, needs user recovery ⚠

**Corvus host is unreachable via its tailnet (`tail.schloschi.com`) address.**
`tailscale ping corvus` works (end-to-end wireguard), but regular `ssh corvus-ts`
times out. The host's `tailscale0` routing was clobbered when I started a second
tailscaled with `network_mode: host`.

Root cause: two tailscaled daemons in the same Linux network namespace fight
over ip rules and the tailnet routing table (both use table 52 by default).
The log hint we saw: `router: somebody (likely systemd-networkd) deleted ip rules; restoring Tailscale's`.

**User cannot recover remotely from here** — needs physical/LAN access to
corvus.

### Recovery steps (ask the user to run on corvus via LAN / console)

```bash
# stop the misbehaving second tailscaled
docker stop tailscale-passer

# bounce the host tailscaled so it rebuilds its ip rules / tailscale0 config cleanly
sudo systemctl restart tailscaled

# sanity
tailscale status | head
```

After this, verify from aquila or schlaeptop:

```bash
ssh corvus-ts 'echo ok; tailscale status | head'
```

The `tailscale-passer` container will be stopped. Leave it stopped (compose
file stays on disk at `~/docker-services/tailscale-passer/compose.yml`) and
do **not** `docker compose up` again — this architecture is dead.

## Why that architecture failed

`network_mode: host` means the container shares the host's net namespace.
Two tailscaled instances in the same netns both:
- Add ip rules at fixed priorities (5210/5230/5250/5270) targeting their own
  tun. First one wins; second overwrites.
- Use routing table `52` by default. They stomp on each other's routes.
- Install netfilter rules — we fixed the backend conflict (image shipped
  `iptables -> iptables-legacy` on an `nftables` host; relinked to
  `iptables-nft`), but the ip-rule/table collision wasn't fixable just by
  that.

Flags we tried that **don't exist** in tailscaled 1.104.2: `--netfilter-kind`.
Real flags: `--netfilter-mode={off,nodivert,on}`, `--tun`, `--state`,
`--socket`. There's no flag to pick a different routing table id — tailscale
hard-codes `52` on Linux as of 1.104.

## Next approach: option 2 — different host as subnet router

Don't run two tailscaleds on corvus. Instead, pick **another host on the
Corvus LAN** to be the subnet router for `ts.passer.schloschi.com`. Corvus
itself keeps its single host-level tailscaled on `tail.schloschi.com`.

**Candidates for the subnet router host** (user needs to pick / provide):
- A Linux VM running on corvus (via libvirt/qemu/lxd/docker-run-but-with-own-netns)
- Another physical device on the Corvus LAN (Pi Zero, old laptop, OpenWRT)
- `gigabyte` (per ssh config: `HostName 192.168.179.203, User hcs, ProxyJump corvus`) — if it's a Linux box the user controls, this is probably the cleanest answer. Ask the user.

### Steps for the next session (once corvus is recovered)

0. Verify corvus is back. `ssh corvus-ts` works, `docker ps` shows no
   `tailscale-passer` running. If `~/docker-services/tailscale-passer/` is
   still there, that's fine — it's just a disk directory now.

1. **Ask the user which host to use as the subnet router.** Ideal is a
   dedicated small Linux host on the Corvus LAN (gigabyte at `.203` is a
   candidate per ssh config; confirm it's suitable and that user has
   sudo there).

2. **On that host, install tailscale directly** (not in a container):
   ```bash
   curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
     | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
   curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
     | sudo tee /etc/apt/sources.list.d/tailscale.list
   sudo apt update && sudo apt install -y tailscale
   # IP forwarding on this host
   sudo tee /etc/sysctl.d/99-tailscale.conf <<'EOF'
   net.ipv4.ip_forward = 1
   net.ipv6.conf.all.forwarding = 1
   EOF
   sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
   ```
   Adjust for distro if the host isn't Debian.

3. **Mint a preauth key on headscale-passer** (not corvus — easy mistake,
   two headscales, got burned by this once):
   ```bash
   ssh aquila 'sudo docker exec -it headscale-passer headscale preauthkeys create --user hannes --expiration 1h'
   ```

4. **Join the passer tailnet, advertise the Corvus LAN**:
   ```bash
   sudo tailscale up \
     --login-server=https://passer.schloschi.com \
     --advertise-routes=192.168.179.0/24 \
     --accept-dns=false \
     --auth-key=<KEY>
   ```

5. **Approve the route on headscale-passer**:
   ```bash
   ssh aquila 'sudo docker exec headscale-passer headscale routes list'
   # find the new route id (the one on this new host, prefix 192.168.179.0/24)
   # route id 3 was the previous attempt — may need to delete that if the stale
   # row is still there. See cleanup below.
   ssh aquila 'sudo docker exec headscale-passer headscale routes enable --route <ID>'
   ```

6. **Clean up stale `corvus` entry in headscale-passer** (from the broken attempt):
   ```bash
   ssh aquila 'sudo docker exec headscale-passer headscale nodes list'
   # find the id of the node named "corvus" (there should be one from the
   # failed container registration). Delete it:
   ssh aquila 'sudo docker exec headscale-passer headscale nodes delete --identifier <ID>'
   ```

7. **On passer, accept routes**:
   ```bash
   ssh passer-ts 'sudo tailscale set --accept-routes=true'
   # verify
   ssh passer-ts 'ip route show | grep 192.168.179'
   ssh passer-ts 'tailscale status'
   ```

8. **Verify reachability from passer to corvus-datahub**:
   ```bash
   ssh passer-ts 'ping -c 2 192.168.179.2'
   ssh passer-ts 'ssh -o StrictHostKeyChecking=accept-new vault@192.168.179.2 echo ok'
   ```
   The user may need to copy a dedicated SSH key to passer first — see
   "Fetch workflow" below.

9. Only then move on to tasks #4 and #5 (fetch workflow — originally the
   point of all this).

## Headscale ACL (worth considering during setup, not required)

headscale 0.23 supports ACL in `policy.hujson`. The user's config.yaml
has `policy.mode: file, path: ""` (empty) → "everything allowed". For the
threat model's "least privilege" ask, set an ACL like:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["passer"],
      "dst": ["192.168.179.2:22", "192.168.179.2:443"]
    }
  ]
}
```

Only enforces what passer may reach on corvus-datahub. Nothing else.
Not blocking for the fetch, but worth doing. Ask the user first.

## Fetch workflow (the actual original goal)

Once passer reaches `192.168.179.2` reliably, the fetch design:

- Create a dedicated local user on **corvus-datahub** (not `vault`) e.g.
  `datahub-sync`, no shell, read-only access to the specific export dir.
- Generate a dedicated ed25519 key pair on **passer**; put the pub key in
  `/home/datahub-sync/.ssh/authorized_keys` on corvus-datahub with
  restrictions: `restrict,command="rrsync -ro /path/to/export",from="100.64.0.2"`.
- `rrsync` (ships with rsync) is the restricted wrapper that locks rsync
  to a specific dir. Install via `apt install rsync` on corvus-datahub.
- systemd service + timer on passer runs the pull every N minutes.
- Known-hosts pin for `192.168.179.2` in `/home/datahub-sync-caller/.ssh/known_hosts` on passer.

See the earlier architecture discussion in-session for the rationale
(push-not-pull was preferred in the original design, but the user is
going with pull here; call it out but don't block on it).

## Open questions for the user (ask next session)

1. Which host on the Corvus LAN should be the subnet router? `gigabyte`
   (`.203`), or something else? Will there be sudo access?
2. What exactly to fetch from corvus-datahub? A directory of files, a DB
   export, a specific service's state? (Needed for the rrsync forced command
   and the systemd timer frequency.)
3. Fetch cadence — every minute, every 15 minutes, hourly, daily?
4. Where does the fetched data land on passer? (Pick a path; probably under
   `/tank/.../datahub/` on passer if it has a tank, or `/var/lib/datahub/`.)
5. Who consumes the mirrored data on the passer / cluster side? (This
   feeds the earlier Home Assistant / MQTT architecture discussion.)

## Minor housekeeping found in-session

- `headscale-corvus` config at `/etc/aquila/headscale/config.yaml` has
  `search_domains: []` (empty). After the base_domain rename, worth setting
  this to `[ts.corvus.schloschi.com]` to match passer-side config pattern.
  Not functionally needed, cosmetic consistency.
- The compose at `~/docker-services/tailscale-passer/compose.yml` on corvus
  is dead code. Either delete it or leave as reference (annotated as broken
  attempt).

## Important: do NOT

- Do not spin up a second tailscaled in `network_mode: host` on any host
  that already runs tailscaled. That caused this incident.
- Do not use the stale `corvus` node row in `headscale-passer` — delete it
  before registering the new subnet router.
- Do not forget: `headscale-corvus` ≠ `headscale-passer`. Each has its own
  users and preauth keys. The URL is the giveaway: the container that trips
  the `http 401` is being pointed at the wrong headscale.
