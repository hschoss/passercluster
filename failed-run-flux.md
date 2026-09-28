Run set -euo pipefail
HelmReleases in the cluster:
NAMESPACE              NAME            AGE   READY   STATUS
cert-manager           cert-manager    91s   True    Helm install succeeded for release cert-manager/cert-manager.v1 with chart cert-manager@1.21.2+634dce9c13b5
envoy-gateway-system   envoy-gateway   91s   True    Helm install succeeded for release envoy-gateway-system/envoy-gateway.v1 with chart gateway-helm@1.9.1+5b99aa5c1d73
podinfo                podinfo         1s            
Structured HelmRelease entries:
  cert-manager|cert-manager
  envoy-gateway-system|envoy-gateway
  podinfo|podinfo
namespace='cert-manager' name='cert-manager'
Waiting for HelmRelease: cert-manager/cert-manager
helmrelease.helm.toolkit.fluxcd.io/cert-manager condition met
namespace='envoy-gateway-system' name='envoy-gateway'
Waiting for HelmRelease: envoy-gateway-system/envoy-gateway
helmrelease.helm.toolkit.fluxcd.io/envoy-gateway condition met
namespace='podinfo' name='podinfo'
Waiting for HelmRelease: podinfo/podinfo
error: timed out waiting for the condition on helmreleases/podinfo
HelmRelease did not become ready: podinfo/podinfo
Name:         podinfo
Namespace:    podinfo
Labels:       kustomize.toolkit.fluxcd.io/name=apps
              kustomize.toolkit.fluxcd.io/namespace=flux-system
Annotations:  <none>
API Version:  helm.toolkit.fluxcd.io/v2
Kind:         HelmRelease
Metadata:
  Creation Timestamp:  2026-09-27T16:07:07Z
  Finalizers:
    finalizers.fluxcd.io
  Generation:        1
  Resource Version:  3754
  UID:               e23c98e7-190e-4dcf-8493-741adcb4cb0f
Spec:
  Chart:
    Spec:
      Chart:               podinfo
      Reconcile Strategy:  ChartVersion
      Source Ref:
        Kind:   HelmRepository
        Name:   podinfo
      Version:  *
  Install:
    Strategy:
      Name:      RetryOnFailure
  Interval:      50m
  Release Name:  podinfo
  Upgrade:
    Strategy:
      Name:  RetryOnFailure
  Values:
    Http Route:
      Enabled:  true
      Hostnames:
        podinfo-e2e.passer.lan
      Parent Refs:
        Name:          envoy
        Namespace:     envoy-gateway-system
        Section Name:  http
        Name:          envoy
6m56s       Warning   Failed               pod/podinfo-redis-dc4cc7457-9vtsp    Error: ErrImagePull
6m56s       Warning   Failed               pod/podinfo-redis-dc4cc7457-9vtsp    Failed to pull image "public.ecr.aws/docker/library/redis:8.6.2": failed to pull and unpack image "public.ecr.aws/docker/library/redis:8.6.2": failed to copy: httpReadSeeker: failed open: unexpected status from GET request to https://public.ecr.aws/v2/docker/library/redis/manifests/sha256:832d7785830f3f4b559300e6191fc914b15642c1935252338825cf4332200148: 429 Too Many Requests...
4m59s       Warning   InstallFailed        helmrelease/podinfo                  Helm install failed for release podinfo/podinfo with chart podinfo@6.15.0: timeout waiting for: [Deployment/podinfo/podinfo-redis status: 'InProgress']...
4m51s       Warning   Failed               pod/podinfo-redis-dc4cc7457-9vtsp    Error: ImagePullBackOff
4m45s       Normal    ArtifactUpToDate     helmrepository/podinfo               artifact up-to-date with remote revision: 'sha256:e7dc68a4dec90a35c2c6d8cdfedb7eaaee17fde45dced5898289df85069ec089'
4m38s       Normal    BackOff              pod/podinfo-redis-dc4cc7457-9vtsp    Back-off pulling image "public.ecr.aws/docker/library/redis:8.6.2"
{"level":"info","ts":"2026-09-27T16:05:14.805Z","logger":"setup","msg":"loading feature gate","ExternalArtifact":true}
{"level":"info","ts":"2026-09-27T16:05:14.812Z","logger":"setup","msg":"starting manager"}
{"level":"info","ts":"2026-09-27T16:05:14.812Z","logger":"controller-runtime.metrics","msg":"Starting metrics server"}
{"level":"info","ts":"2026-09-27T16:05:14.812Z","logger":"controller-runtime.metrics","msg":"Serving metrics server","bindAddress":":8080","secure":false}
{"level":"info","ts":"2026-09-27T16:05:14.812Z","msg":"starting server","name":"health probe","addr":"[::]:9440"}
{"level":"info","ts":"2026-09-27T16:05:14.913Z","logger":"runtime","msg":"Attempting to acquire leader lease...","lock":"flux-system/helm-controller-leader-election"}
{"level":"info","ts":"2026-09-27T16:05:14.917Z","logger":"runtime","msg":"Successfully acquired lease","lock":"flux-system/helm-controller-leader-election"}
{"level":"info","ts":"2026-09-27T16:05:14.917Z","msg":"Starting EventSource","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","source":"kind source: *v1.ExternalArtifact"}
{"level":"info","ts":"2026-09-27T16:05:14.917Z","msg":"Starting EventSource","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","source":"kind source: *v2.HelmRelease"}
{"level":"info","ts":"2026-09-27T16:05:14.917Z","msg":"Starting EventSource","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","source":"kind source: *v1.PartialObjectMetadata[v1 ConfigMap]"}
{"level":"info","ts":"2026-09-27T16:05:14.917Z","msg":"Starting EventSource","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","source":"kind source: *v1.PartialObjectMetadata[v1 Secret]"}
{"level":"info","ts":"2026-09-27T16:05:14.917Z","msg":"Starting EventSource","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","source":"kind source: *v1.HelmChart"}
{"level":"info","ts":"2026-09-27T16:05:14.917Z","msg":"Starting EventSource","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","source":"kind source: *v1.OCIRepository"}
{"level":"info","ts":"2026-09-27T16:05:15.120Z","msg":"Starting Controller","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease"}
{"level":"info","ts":"2026-09-27T16:05:15.120Z","msg":"Starting workers","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","worker count":4}
{"level":"info","ts":"2026-09-27T16:05:37.985Z","msg":"metadata.finalizers: \"finalizers.fluxcd.io\": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"cert-manager","namespace":"cert-manager"},"namespace":"cert-manager","name":"cert-manager","reconcileID":"3c1d68bf-bea7-4954-b85e-9f6977417d4a"}
{"level":"info","ts":"2026-09-27T16:05:37.988Z","msg":"metadata.finalizers: \"finalizers.fluxcd.io\": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"envoy-gateway","namespace":"envoy-gateway-system"},"namespace":"envoy-gateway-system","name":"envoy-gateway","reconcileID":"ceb6bc5f-7233-4050-ae1a-6c276b9bfa75"}
{"level":"info","ts":"2026-09-27T16:05:38.746Z","msg":"OCIRepository 'cert-manager/cert-manager' is not ready: latest generation of object has not been reconciled","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"cert-manager","namespace":"cert-manager"},"namespace":"cert-manager","name":"cert-manager","reconcileID":"5cbd7c73-7dea-46d6-a95c-f841d9626d8d"}
{"level":"info","ts":"2026-09-27T16:05:38.747Z","msg":"OCIRepository 'envoy-gateway-system/gateway-helm' is not ready: latest generation of object has not been reconciled","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"envoy-gateway","namespace":"envoy-gateway-system"},"namespace":"envoy-gateway-system","name":"envoy-gateway","reconcileID":"9d58493c-0817-4508-828c-450ad450bc60"}
{"level":"info","ts":"2026-09-27T16:05:39.829Z","msg":"release not installed: no release in storage for object","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"envoy-gateway","namespace":"envoy-gateway-system"},"namespace":"envoy-gateway-system","name":"envoy-gateway","reconcileID":"95ab1c49-29de-441c-9ada-ebbdc544fc56"}
{"level":"info","ts":"2026-09-27T16:05:39.837Z","msg":"running 'install' action with timeout of 5m0s","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"envoy-gateway","namespace":"envoy-gateway-system"},"namespace":"envoy-gateway-system","name":"envoy-gateway","reconcileID":"95ab1c49-29de-441c-9ada-ebbdc544fc56"}
{"level":"info","ts":"2026-09-27T16:05:40.211Z","msg":"release not installed: no release in storage for object","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"cert-manager","namespace":"cert-manager"},"namespace":"cert-manager","name":"cert-manager","reconcileID":"65fca903-d584-4089-b7ae-e5e30eb6434d"}
{"level":"info","ts":"2026-09-27T16:05:40.225Z","msg":"running 'install' action with timeout of 5m0s","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"cert-manager","namespace":"cert-manager"},"namespace":"cert-manager","name":"cert-manager","reconcileID":"65fca903-d584-4089-b7ae-e5e30eb6434d"}
{"level":"info","ts":"2026-09-27T16:06:04.125Z","msg":"release in-sync with desired state","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"cert-manager","namespace":"cert-manager"},"namespace":"cert-manager","name":"cert-manager","reconcileID":"65fca903-d584-4089-b7ae-e5e30eb6434d"}
{"level":"info","ts":"2026-09-27T16:06:05.322Z","msg":"release in-sync with desired state","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"envoy-gateway","namespace":"envoy-gateway-system"},"namespace":"envoy-gateway-system","name":"envoy-gateway","reconcileID":"95ab1c49-29de-441c-9ada-ebbdc544fc56"}
{"level":"info","ts":"2026-09-27T16:07:07.993Z","msg":"metadata.finalizers: \"finalizers.fluxcd.io\": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"71be4b0e-0087-406a-a2f4-172cdd69fd0a"}
{"level":"info","ts":"2026-09-27T16:07:08.753Z","msg":"Created HelmChart/podinfo/podinfo-podinfo with SourceRef 'HelmRepository/podinfo/podinfo'","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"1f3510f0-b9ea-4fb1-8053-8a3b25e59d65"}
{"level":"info","ts":"2026-09-27T16:07:08.766Z","msg":"HelmChart 'podinfo/podinfo-podinfo' is not ready: latest generation of object has not been reconciled","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"1f3510f0-b9ea-4fb1-8053-8a3b25e59d65"}
{"level":"info","ts":"2026-09-27T16:07:08.986Z","msg":"HelmChart/podinfo/podinfo-podinfo with SourceRef 'HelmRepository/podinfo/podinfo' is in-sync","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"bf8ecf87-0c23-4728-8a8f-989a2fc8b031"}
{"level":"info","ts":"2026-09-27T16:07:08.991Z","msg":"release not installed: no release in storage for object","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"bf8ecf87-0c23-4728-8a8f-989a2fc8b031"}
{"level":"info","ts":"2026-09-27T16:07:09.001Z","msg":"running 'install' action with timeout of 5m0s","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"bf8ecf87-0c23-4728-8a8f-989a2fc8b031"}
{"level":"info","ts":"2026-09-27T16:12:09.350Z","msg":"release is in a failed state","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"bf8ecf87-0c23-4728-8a8f-989a2fc8b031"}
{"level":"info","ts":"2026-09-27T16:16:57.495Z","msg":"HelmChart/podinfo/podinfo-podinfo with SourceRef 'HelmRepository/podinfo/podinfo' is in-sync","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"3ed49667-ff87-4647-9f4a-bf9efbe432d4"}
{"level":"info","ts":"2026-09-27T16:16:57.514Z","msg":"release is in a failed state","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"3ed49667-ff87-4647-9f4a-bf9efbe432d4"}
{"level":"info","ts":"2026-09-27T16:16:57.525Z","msg":"running 'upgrade' action with timeout of 5m0s","controller":"helmrelease","controllerGroup":"helm.toolkit.fluxcd.io","controllerKind":"HelmRelease","HelmRelease":{"name":"podinfo","namespace":"podinfo"},"namespace":"podinfo","name":"podinfo","reconcileID":"3ed49667-ff87-4647-9f4a-bf9efbe432d4"}
Error: Process completed with exit code 1.

