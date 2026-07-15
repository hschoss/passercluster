# Next Session Prompt

You are operating the repo `~/gh/passercluster`.

Current focus:

- `authentik` is installed and healthy.
- `immich` is healthy and the Gateway route is accepted.
- `apps` is blocked by the `nextcloud` HelmRelease failing its rollout.
- Local workstation DNS is not resolving `*.passer.lan` through the cluster DNS path.

Do next:

1. Fix the stalled `nextcloud` deployment so Flux can finish the `apps` kustomization.
2. Verify LAN DNS forwarding to CoreDNS or Pi-hole so `immich.passer.lan` resolves from clients.
3. Continue the Authentik edge-auth rollout by creating proxy providers and gateway policies.
4. Re-check the app routes end to end after the DNS and rollout issues are cleared.
