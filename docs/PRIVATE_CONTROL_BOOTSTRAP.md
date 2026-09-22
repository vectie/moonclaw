# MoonDesk–MoonClaw private control bootstrap

Both processes must share an operator-owned private configuration. Do not
disable authentication or put the token in a URL, browser response, unit file,
command line, or log.

Run the checked MoonBit automation with explicit canonical paths:

```text
moon run scripts/bootstrap-private-control.mbtx init WORKSPACE APP_DATA WORKSPACE_ID
```

It creates `APP_DATA/control/execution-sandbox/moonclaw.json`, using secure
entropy for a 32-character instance identifier and a 64-character token.
The directory is mode 0700 and the file 0600. It reuses matching existing
configuration and refuses to overwrite a conflicting workspace binding.
The workspace must already exist; neither it nor the private control path
may resolve through a symlink. Run as the account owning both services.

Set these same path-only environment variables on both processes, retaining
their existing runtime, workspace, MoonGate, and provider configuration:

```text
LEPUSA_APP_DATA_DIR=APP_DATA
MOONDESK_EXECUTION_SANDBOX_CONFIG=APP_DATA/control/execution-sandbox/moonclaw.json
```

Restart both processes after changing their environment. The MoonClaw daemon
must serve the exact `workspace_root` in the configuration; MoonDesk binds
authenticated requests to its corresponding daemon status path and verifies
the instance identifier in every control response.

Probe without exposing the token:

```text
moon run scripts/bootstrap-private-control.mbtx probe CONFIG http://127.0.0.1:PORT
```

An unauthenticated request to `/v1/moongate-route` must return 401 after setup.
The authenticated probe requires HTTP 200 and the matching instance header.
Authentication success and model availability are distinct: inspect `ready`
and `error` in the returned route. The script does not deploy/restart services,
grant users permissions, or provision an inference provider.

## Retain the real MoonGate route

Keep the workspace's existing `.moonsuite/suite-status.json` on upgrade.
MoonClaw discovers MoonGate through its validated status/manifest contracts
and `manifest.baseUrl`; the live `/openclaw/v1/models` catalog determines
available `moongate/` model names. Do not replace that catalog with a static
claim that an old model remains available. Existing provider secrets and
MoonGate control tokens stay in their private service configuration.

For an isolated canary, a private copy of that status file may point to the
same live MoonGate for read-only health/catalog probing. Do not share the
canary's private control credentials with production. Provision a separate
production instance binding to the production workspace before switching.

2026-09-22 verification: an isolated Linux MoonClaw 0.1.7+2788.8be36b95
accepted the paired configuration, rejected unauthenticated access with 401,
and returned an authenticated, instance-bound ready route through loopback
MoonGate. Its live catalog was `GLM-5.3-Flash-EXL3`, not the older Qwen alias.
This verifies control/catalog access, not a newly executed inference request.
