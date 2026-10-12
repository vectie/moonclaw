# Inspect an interrupted artifact return

An interrupted return stays unresolved. Destination inspection is a separate,
bounded, read-only operation for the exact saved pending attempt. It cannot
retry a return, unlock retention, roll back a destination, promote an artifact,
or turn observed bytes into a historical success receipt.

## Owner workflow

Open the gateway's normal `/ui` owner overview and expand **Inspect an
interrupted artifact return**. Enter the instance, workspace, retention, and
original pending attempt identifiers supplied by the host's pending-return
reference. Use the existing gateway access control and the execution route
token. The latter is held only in this view and is cleared on context change
or **Clear observation and token**; it is not persisted.

Choose **Inspect destination read-only**. The view reports one of five states:

- `desired-applied`: observed content matches the reviewed output; the earlier
  return is still not proven to have succeeded.
- `reviewed-prestate`: observed content matches the pre-return reviewed state.
- `diverged`: safely observed content matches neither reviewed state.
- `unavailable`: safe inspection could not establish the destination state.
- `manual-recovery`: the historical trusted workspace-root binding is unproven.

Every result names the exact pending attempt and safe relative destination,
shows its observation time, and keeps retry disabled. It is a point-in-time
observation. Changing selection, navigation, gateway access, or clearing the
view invalidates its projection. A failed refresh clears the previous result
and explains that no current observation is available. A late response for an
older generation or different attempt cannot revive it.

Preserve the pending return, Fort claim pair, and destination for a separate
operator-reviewed recovery decision. No recovery decision is implemented here.

## Trusted operator configuration

The existing promotion launcher remains under
`MOONCLAW_MOONFORT_PROMOTION_CONFIG`. Independently configure
`MOONCLAW_MOONFORT_RECOVERY_CONFIG` as a canonical operator-owned JSON file:

```json
{
  "protocol_version": 1,
  "inspector_path": "/operator-selected/bin/inspect-promotion-recovery",
  "inspector_args": [],
  "executor_config_path": "/operator-selected/fort-registry.json",
  "receipt_root": "/operator-selected/claw-receipts"
}
```

The recovery and promotion launchers must name the same executor registry and
receipt root. These paths and fixed argv are never accepted from UI requests.
The inspector runs directly, without a shell or inherited process environment,
with a ten-second deadline, a 4 KiB input ceiling and a 16 KiB output ceiling.
The only Fort stdin fields are protocol version 4 and the saved retention ID.
Fort independently enforces its existing claim, grant-digest, registered-root,
root-identity, stable-read and no-follow destination constraints.

The existing `MOONDESK_EXECUTION_SANDBOX_CONFIG` binds the instance, workspace,
and route token. Inspection uses its nonmutating loader: private owned 0700
control directory and 0600 regular configuration file must already exist.
Unsafe permissions are refused; inspection does not chmod them into compliance.

## Bounded API

Both the daemon and gateway register
`POST /v1/execution-sandbox/promotion-recovery`. Gateway requests require its
configured bearer authentication as well as the existing
`x-moonclaw-execution-token`; the daemon requires the execution token. The body
is at most 4 KiB and has exactly these six fields:

```json
{
  "protocol_version": 1,
  "instance_id": "opaque-instance-id",
  "workspace_id": "opaque-workspace-id",
  "retention_id": "opaque-retention-id",
  "pending_attempt_id": "original-return-request-id",
  "request_id": "this-read-correlation-id"
}
```

Extra fields, trusted paths, changed pending identities, active exclusive
return locks, missing/terminal checkpoints, wrong bindings, contradictory
state digests and malformed provider output are refused. The host opens only
the existing shared lock and bounded pending record, validates the stored
reviewed selection, invokes Fort, then rereads the pending selection before
returning the observation. No new receipt or lock file is created.

The response always has `pending_attempt=true`, `retry_allowed=false`, and
`historical_success_confirmed=false`. Provider error text, private paths,
native status, file content and root inode/device identities are not exposed.
Responses are `Cache-Control: no-store`. The normal owner UI entry is
revalidated with `no-cache`; newly packaged compiler and loader entries are
content-hashed so an older bootstrap cannot masquerade as this build.

The daemon's existing promotion/receipt failure may include a `pending_return`
navigation reference, but only after the stored pending selection exactly
matches the authenticated request. It uses the original saved attempt ID,
never the ID of a later receipt lookup. Discovering that reference does not
inspect or mutate the destination.

## Qualification boundary

Round55 uses private deterministic-content locked claims and real native Fort
inspection through both Claw HTTP routes, plus compiled owner transport/state
and DOM rendering. It is a local fixture qualification, not evidence of a
configured production operator identity, provider, microVM, deployment,
graphical browser session, or actual historical promotion.

The retained compiler-JS packaging recipe updates the normal dist bootstrap
to a fresh compiler entry while retaining historical assets. This is not a
Vite rebuild. The inherited auxiliary `scripts/bundle` graph still lacks its
declared local `../../async`; no dependency or vendor workaround is applied.
