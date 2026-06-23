# Current State

Date: 2026-06-23

## What Is Healthy

- Control plane `192.168.178.200` is back and `Ready`.
- Workers `192.168.178.201`, `192.168.178.202`, and `192.168.178.203` are all `Ready`.
- Talos extensions are present on the repaired nodes:
  - `200`: `iscsi-tools`, `util-linux-tools`
  - `202`: `iscsi-tools`, `util-linux-tools`
- Flux `flux-system`, `infra-configs`, `infra-controllers`, and `apps` are `Ready`.
- Longhorn is healthy again.
- Main app workloads are running:
  - `nextcloud`
  - `immich`
  - `jellyfin`
  - `vaultwarden`
  - `paperless-ngx`
  - `podinfo`

## What Was Missing / What Still Needs Attention

- The Velero bootstrap job `minio-bucket-setup` is still present in the cluster and is stuck in `ImagePullBackOff` because it was created with an invalid MinIO client tag.
- The repository manifest has been updated to a valid `quay.io/minio/mc` release tag, but the live Job still needs to be recreated or re-applied so it can finish and create the `velero` bucket.
- `flux get kustomizations` still shows `infra-velero` as `Unknown` while that job is unresolved, and `infra-velero-schedules` is blocked on it.

## Notes

- Worker `202` had to be uncordoned after the Talos recovery flow.
- Current cluster versions are mixed:
  - `200` and `202`: Talos `v1.13.4`
  - `201` and `203`: Talos `v1.13.2`
- The application layer recovered after Longhorn was fixed on the nodes that were missing the storage extensions.
