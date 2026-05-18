• Implemented the Longhorn GitOps/Talos scaffolding.

  - Added Longhorn Helm install with replica count 1, best-effort locality/autobalance, S3 backup target, and no default class: infrastructure/controllers/longhorn.yaml:24
  - Added Flux wiring and longer controller timeout: infrastructure/controllers/kustomization.yaml:7, infrastructure/configs/kustomization.yaml:8, clusters/production/infrastructure.yaml:10
  - Added node labels plus Longhorn node/disk tag config for nodes 201–203: infrastructure/configs/longhorn-node-labels.yaml:1
  - Added new app StorageClasses and recurring jobs: infrastructure/configs/longhorn-storage-classes.yaml:1, infrastructure/configs/longhorn-recurring-jobs.yaml:1
  - Added Talos node disk patches and operator scripts: talos/patches/node-201-longhorn.patch.yaml:1, scripts/longhorn-validate-disks.sh:1, scripts/longhorn-health-check.sh:1
  - Added PVC templates, monitoring manifests, and ops docs: infrastructure/configs/longhorn-application-pvcs.yaml:1, infrastructure/configs/longhorn-monitoring.yaml:1, infrastructure/longhorn-README.md:1

  Validation run:

  - kubectl kustomize infrastructure/controllers
  - kubectl kustomize infrastructure/configs
  - kubectl apply --dry-run=server -k infrastructure/controllers
  - kubectl apply --dry-run=server -k infrastructure/configs
  - kubectl apply --dry-run=server -f clusters/production/infrastructure.yaml
  - bash -n scripts/longhorn-*.sh
  - git diff --check

  Notes:

  - longhorn-monitoring.yaml is intentionally not applied yet because Prometheus Operator CRDs are not installed.
  - scripts/longhorn-validate-disks.sh could not query Talos with the current local Talos config due TLS verification failure; the script now reports that explicitly.
  - Existing uncommitted/deleted files were already present in the worktree, including old talos/patches/talos-*-disks.yaml deletions.

─ Worked for 10m 22s ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
Token usage: total=205,054 input=182,504 (+ 2,678,400 cached) output=22,550 (reasoning 5,543)
To continue this session, run codex resume 019e353a-a0fb-7ae0-a931-48a4aec65cd7
