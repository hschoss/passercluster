# Command reference

Copy-paste friendly. Every command assumes:

```bash
cd ~/gh/passercluster
export KUBECONFIG=$PWD/talos/kubeconfig
export TALOSCONFIG=$PWD/talos/talosconfig
```

## Flux

```bash
# what's the whole cluster doing?
flux get kustomizations -A
flux get helmreleases -A
flux get sources all -A

# force-pull the latest commit
flux reconcile source git flux-system -n flux-system

# reconcile a specific layer (fast → slow)
flux reconcile kustomization infra-controllers  -n flux-system
flux reconcile kustomization infra-configs      -n flux-system
flux reconcile kustomization apps               -n flux-system
flux reconcile kustomization infra-velero       -n flux-system

# diagnose a stuck one
flux -n flux-system describe kustomization <name>
flux -n <ns>          describe helmrelease   <name>

# pause / resume
flux -n flux-system suspend kustomization <name>
flux -n flux-system resume  kustomization <name>
```

## Kubernetes

```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get httproute -A
kubectl get gateway -A
kubectl get svc -A
kubectl get certificate -A
kubectl -n <ns> describe pod <name>
kubectl -n <ns> logs deploy/<name> --tail=100
kubectl -n <ns> logs deploy/<name> -f
kubectl -n <ns> rollout status deploy/<name>
kubectl -n <ns> rollout restart deploy/<name>
```

## Talos

```bash
# health of a specific node
talosctl -n 192.168.178.200 health

# interactive TUI (CPU, memory, disk, containers, dmesg)
talosctl -n 192.168.178.200 dashboard

# stream a service log
talosctl -n 192.168.178.201 logs kubelet -f

# reboot (kexec — ~60 s)
talosctl -n 192.168.178.201 reboot

# force-reboot when the node is unresponsive
talosctl -n 192.168.178.200 reboot --mode force

# refresh kubeconfig from Talos
talosctl -n 192.168.178.200 kubeconfig talos/kubeconfig
```

## SOPS

```bash
# edit an encrypted secret in place (opens $EDITOR, saves re-encrypted)
sops apps/base/<app>/<file>.secret.yaml

# print plaintext to stdout (careful — do not paste anywhere)
sops --decrypt apps/base/<app>/<file>.secret.yaml

# encrypt a freshly written plaintext file in place
sops --encrypt --in-place path/to/new.secret.yaml

# check every *.secret.yaml is actually encrypted before pushing
grep -L 'ENC\[' $(find apps infrastructure -name '*.secret.yaml')
# anything printed by the above is plaintext and must be fixed
```

## Longhorn

```bash
# health board
kubectl -n longhorn-system get nodes.longhorn.io
kubectl -n longhorn-system get volumes | head
kubectl -n longhorn-system get replicas.longhorn.io | head

# the compact status helper
scripts/longhorn-health-check.sh
scripts/longhorn-validate-disks.sh

# UI
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# or https://longhorn.passer.lan
```

## Velero

```bash
kubectl -n velero get backup
kubectl -n velero get schedule
kubectl -n velero get restore

# ad-hoc backup
velero backup create manual-$(date +%Y%m%d-%H%M) --include-namespaces=<ns>

# restore (see docs/VELERO-SETUP.md for the full recipe)
velero restore create --from-backup <backup-name>
```

## DNS + HTTP probes

```bash
# does DNS resolve at all?
nslookup nextcloud.passer.lan
nslookup nextcloud.passer.lan 192.168.178.241   # ask CoreDNS directly

# is the Gateway serving?
curl -skI https://nextcloud.passer.lan/ --max-time 5

# bypass DNS entirely (test the Gateway even if Pi-hole is broken)
curl -skI --resolve nextcloud.passer.lan:443:192.168.178.240 \
     https://nextcloud.passer.lan/ --max-time 5
```

## HelmRelease values inspection

```bash
# effective values a HelmRelease has been rendered with
kubectl -n <ns> get helmrelease <name> -o yaml | yq '.spec.values'

# per-app config maps / secrets it consumes
kubectl -n <ns> get cm,secret
```

## Repo-side sanity checks

```bash
# render production without applying
kubectl kustomize --load-restrictor=LoadRestrictionsNone apps/production >/dev/null && echo OK

# render a single base app
kubectl kustomize --load-restrictor=LoadRestrictionsNone apps/base/<app>

# what would flux apply?
flux build kustomization apps --path apps/production 2>&1 | head
```
