# Command Reference

Small set of commands that come up repeatedly during cluster work.

## Flux

```bash
flux get kustomizations -A
flux get helmreleases -A
flux get sources all -A
flux reconcile kustomization infra-controllers -n flux-system
flux reconcile kustomization infra-configs -n flux-system
flux reconcile kustomization apps -n flux-system
```

## Kubernetes

```bash
kubectl get pods -A
kubectl get httproute -A
kubectl get gateway -A
kubectl get certificate -A
kubectl get svc -A
kubectl logs -n external-dns deploy/external-dns --tail=100
```

## DNS and HTTP

```bash
nslookup immich.passer.lan
nslookup immich.passer.lan 192.168.178.241
curl -I http://immich.passer.lan
curl -k -I https://immich.passer.lan
```

## Talos

```bash
cd ~/gh/passercluster/talos
talosctl health --nodes 192.168.178.200 --endpoints 192.168.178.200 --talosconfig ./talosconfig
talosctl dashboard --nodes 192.168.178.200 --endpoints 192.168.178.200 --talosconfig ./talosconfig
```
