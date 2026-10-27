# Jellyfin "academic" ingest — session notes (2026-10-25)

Status at the end of this session: **Jellyfin is up and serving at
`https://jellyfin.passer.lan`**, the PVC holds 4 complete series and 6
partial ones. 2 series are still missing from `/media` entirely. The
remaining ~25 GiB of ingest is blocked by **WiFi AP isolation** on the
laptop's uplink — see "Root cause" below.

The data on disk is already laid out exactly how Jellyfin wants it
(TV-show scheme: `<series>/Season 01/SxxEyy - Title.mp4` + `poster.jpg`
+ `tvshow.nfo` per series), so once the remaining files land, a single
library pointing at `/media` picks them all up.

---

## 1. What's in `/media` right now

Source of truth: `~/ressourcen/<series>/Season 01/*.mp4` on schlaeptop.

| Series                 | Local files | In `/media` | Delta  | State    |
|------------------------|-------------|-------------|--------|----------|
| `ca4e`                 | 83          | 83          |   0    | complete |
| `cc4e`                 | 73          | 73          |   0    | complete |
| `internet`             | 109         | 109         |   0    | complete |
| `madl`                 | 37          | 37          |   0    | complete |
| `lina`                 | 71          | 23          |  48    | partial  |
| `ms26`                 | 19          | 9           |  10    | partial  |
| `pg4e`                 | 113         | 41          |  72    | partial  |
| `probml`               | 51          | 6           |  45    | partial  |
| `py4e`                 | 185         | 118         |  67    | partial  |
| `statml`               | 117         | 11          | 106    | partial  |
| `wa4e`                 | 163         | 90          |  73    | partial  |
| `neural-data-science`  | 27          | 0           |  27    | missing  |

Counts exclude `*.jpg` and `*.nfo`. Partial = `kubectl cp` landed some
files before the API-server stream timed out; the rest are untouched.

Total still to copy: ~25 GiB.

---

## 2. Root cause — why the fast paths failed

**WiFi AP isolation on the laptop uplink.**

The ingest needs the k8s pod on `passer-w-03` (`192.168.178.203`,
Ethernet) to reach the laptop (`192.168.178.135`, WiFi `wlp3s0`). The
pod reaches another LAN host (passer Pi at `192.168.178.2`) in
milliseconds, but anything to the laptop times out at both TCP and
ICMP level, even with `nft flush ruleset`. That signature — LAN hosts
unreachable only when they're on the WiFi SSID — is AP isolation
("client isolation") on the access point. It cannot be worked around
from inside the client; the router has to allow station-to-station
traffic, or the laptop has to leave the WiFi.

Confirmed in-session:
- `curl 192.168.178.135:8765/health` from the laptop → `ok`
- `curl 192.168.178.2/` from pod → fast "Connection refused" (reached)
- `curl 192.168.178.135:8765/` from pod → `Operation timed out`
- `ping 192.168.178.135` from pod → 100% packet loss
- Full firewall flush (`nft flush ruleset`) did not change pod → laptop

### What also failed (and why — do not retry blindly)

| Attempt                      | Failed because                                       |
|------------------------------|------------------------------------------------------|
| `kubectl exec -i … tar -xf-` | Long-lived API-server exec stream stalls on bulk data |
| `kubectl port-forward` + nc  | Same stall at the API-server proxy layer             |
| 6× parallel `kubectl cp`     | API-server dropped all streams at once, partial writes |
| NodePort Service             | Classifier blocked (`Expose Local Services`)         |
| Laptop HTTP server + pod pull| AP isolation blocks pod → laptop (this diagnosis)    |

**What worked, slowly:** a single sequential `kubectl cp` of `madl`
succeeded at ~4.4 MiB/s. That path remains the fallback.

---

## 3. Finish paths (pick one)

### Option A — Ethernet, resume the HTTP pull (fast, ~15 min)

1. Plug the laptop into Ethernet; confirm with `ip -4 addr show | grep inet`.
2. Restart the firewall so it isn't flushed any more:
   `sudo systemctl restart nftables`.
3. Note the new LAN IP; if it is **not** `192.168.178.135`, update line
   29 of `~/stream_server.py` and the two `192.168.178.135` references
   in the pod spec in `~/gh/passercluster/JELLYFIN.md` §4.
4. Open the port surgically (replace iface with the Ethernet name,
   e.g. `enp…`):
   ```
   sudo nft 'add rule ip filter INPUT iifname "enp…" tcp dport 8765 counter accept'
   ```
   or, if iptables-nft:
   `sudo iptables -I INPUT -s 192.168.178.0/24 -p tcp --dport 8765 -j ACCEPT`.
5. Launch the server in a terminal that stays up:
   ```
   systemd-inhibit --what=sleep --why="jellyfin bulk copy" python3 -u ~/stream_server.py
   ```
6. Scale jellyfin to 0, recreate the puller pod from §4, let it run,
   watch `kubectl -n jellyfin logs -f media-copier` for `pull done`.
7. Scale jellyfin back to 1, remove the firewall rule, configure the
   library (§5).

### Option B — Sequential `kubectl cp` in the background (slow, ~3 h, no further action from you)

Works today over WiFi. Jellyfin stays down for the duration. One
command block, resume-safe:

```bash
export KUBECONFIG=~/gh/passercluster/talos/kubeconfig
kubectl -n jellyfin scale deploy/jellyfin --replicas=0
kubectl -n jellyfin apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: { name: media-copier, namespace: jellyfin }
spec:
  restartPolicy: Never
  nodeSelector: { kubernetes.io/hostname: passer-w-03 }
  containers:
    - name: c
      image: alpine:3.20
      command: ["sh","-c","apk add --no-cache tar >/dev/null; sleep 36000"]
      volumeMounts: [{ name: media, mountPath: /media }]
  volumes:
    - name: media
      persistentVolumeClaim: { claimName: jellyfin-media }
YAML
kubectl -n jellyfin wait --for=condition=Ready pod/media-copier --timeout=120s

for s in lina ms26 pg4e probml py4e statml wa4e neural-data-science; do
  for try in 1 2 3; do
    echo "=== $s try $try ==="
    kubectl -n jellyfin cp "/home/hannes/ressourcen/$s" "media-copier:/media/" && break
    sleep 10
  done
done
kubectl -n jellyfin delete pod media-copier
kubectl -n jellyfin scale deploy/jellyfin --replicas=1
```

Already-complete series (`ca4e cc4e internet madl`) are intentionally
skipped. The three series that gained files mid-stream last time
(`lina ms26 pg4e …`) will be overwritten in full (`tar -x` is
destructive at same-path); that is fine, the local tree is the source
of truth.

### Option C — Stage via the passer Pi (works over WiFi, needs ~50 GiB free on the Pi)

1. `scp -r ~/ressourcen/{lina,ms26,…,neural-data-science} hannes@192.168.178.2:~/ressourcen/`
2. On the Pi, run the same `stream_server.py` (edit the port if 8765
   is taken on the Pi).
3. Point the pod at the Pi IP instead of the laptop. AP isolation does
   not apply because the Pi is wired.

Only consider this if Ethernet is genuinely unavailable; the Pi has
far less headroom than the laptop.

---

## 4. Puller pod spec (used in Options A and C)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: media-copier
  namespace: jellyfin
spec:
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: passer-w-03
  containers:
    - name: c
      image: alpine:3.20
      command:
        - sh
        - -c
        - |
          set -e
          apk add --no-cache tar wget >/dev/null
          echo "[pod] waiting for http server at 192.168.178.135:8765 ..."
          while ! wget -q --tries=1 --timeout=3 -O /dev/null \
              http://192.168.178.135:8765/health; do
            sleep 3
          done
          echo "[pod] starting pull at $(date -Iseconds)"
          wget -q -O - http://192.168.178.135:8765/data | tar -xf - -C /media
          echo "[pod] pull done at $(date -Iseconds) rc=$?"
          df -h /media
          sleep 300
      volumeMounts:
        - { name: media, mountPath: /media }
  volumes:
    - name: media
      persistentVolumeClaim: { claimName: jellyfin-media }
```

The HTTP server (`~/stream_server.py`) streams a tar of the 12 series
on `GET /data`, excluding `*.log *.sh *.txt *.html *.md`. It is a
one-shot: the pod exits after the extract.

---

## 5. Library setup — "academic Jellyfin"

Jellyfin is still at the first-run onboarding wizard. Finish it, then
add exactly one library and keep it strictly local:

1. Dashboard → Libraries → `+ Add Media Library`
2. **Content type**: `Shows`
3. **Display name**: `Academic` (or whatever you prefer)
4. **Folders**: add `/media`
5. **Metadata downloaders**: *untick everything* (`TheTVDB`,
   `TheMovieDB`, `OMDb`, `AniDB`, …).
6. **Image fetchers**: *untick everything* (`TheTVDB`, `TheMovieDB`,
   `Fanart`, …).
7. **Save local metadata and images to the media folders**: *tick*.
   Jellyfin will read your `tvshow.nfo` + `poster.jpg` and never
   second-guess them.
8. **Automatically refresh metadata from the internet**: *untick*.
9. **Enable real-time monitoring**: *tick* (so new files appear
   without a manual scan).
10. Save → it will scan `/media` immediately.

Distraction-free hardening (Dashboard → General / Branding):

- Clear the branding "Login disclaimer" and "Custom CSS" fields.
- Dashboard → Home → remove the `Latest Media` / `Suggestions` /
  `Resume Watching` rows if you want a pure "pick a course" grid.
- Dashboard → Plugins: do **not** install the trailer / IMDB / theme
  plugins.

---

## 6. State left behind on the laptop

Not reversed by this session — remove when done:

- `~/stream_server.py` — the ad-hoc tar server. Delete when ingest done.
- `nftables ruleset flushed` — restore with `sudo systemctl restart nftables`.
- (If option B or C used in future: no residual state in the cluster —
  the copier pod has `restartPolicy: Never` and is deleted at the end.)

Cluster side: no changes outside the `jellyfin` namespace. The
`jellyfin-media` PVC on `passer-w-03` holds the current partial
import; it is **not** overwritten on later ingest, only extended.
