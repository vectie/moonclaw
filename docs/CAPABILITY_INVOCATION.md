# Generic installed-pack capability invocation

MoonClaw executes cross-product work through one generic runtime seam. It does
not recognize product names or invented canvas verbs.

## Required truth

An executable operation must be present in all of the following:

1. an active, receipt-verified installed `pack.json`;
2. a compiled `moonflow.capability-catalog.v1`;
3. a version-matched `moonflow.adapter-declaration.v1` using
   `moonflow.adapter.v2`;
4. an unexpired `moonflow.adapter-health.v1` whose evidence bytes still match
   its SHA-256 digest; and
5. a pack-owned executor with reconciliation support.

Canonical identities have these forms:

```text
operation: <product-id>/<tool-id>@<pack-version>
schema:    <product-id>/<schema-id>@<schema-version>
```

MoonClaw independently compares the selected catalog row with the active
manifest at invocation time. Product, pack and tool ownership, pack version,
input/output schema versions, authority, idempotency, review requirement,
adapter identity and health window must match exactly. The requested claim must
also be recognized and remain at or below the catalog adapter's claim ceiling.

## Runtime call

The public MoonBit seam is:

```text
@packtool.execute_installed_capability_v1(
  workspace=...,
  catalog_json=...,
  invocation=...,
  executor=...,
  policy=...,
)
```

`CapabilityInvocationV1` contains the wire-compatible MoonFlow adapter request,
the selected adapter ID, evaluation/result times, an attempt number, and
pack-opaque input/configuration. `CapabilityInvocationPolicyV1` supplies the
host's authority grants, exact versioned review receipts, timeout, retry and
cost ceilings.

Portable wire examples are available as
[`moonflow-pack-capability-invocation.v1.json`](examples/moonflow-pack-capability-invocation.v1.json)
and
[`moonflow-pack-capability-policy.v1.json`](examples/moonflow-pack-capability-policy.v1.json).
The zero digests in the invocation example are placeholders; the host must
replace them with MoonFlow's verified aggregate input digest.

The pack-owned executor remains an existing `PackToolExecutor`. For this path
it must also provide `reconcile`, keyed by the same immutable request and
idempotency identity.

## Gateway HTTP boundary

The loopback gateway exposes the same runtime seam without creating another
runtime:

```text
POST /v1/capability/submit
POST /v1/capability/reconcile
POST /v1/capability/status
```

All three accept one bare `moonclaw.capability-invocation.v1` object. Successful
responses are the bare `moonclaw.capability-invocation-receipt.v1` object, so a
pack host such as MoonFind can append it without translating identity fields.
`status` is observation-only. `reconcile` refuses to create a missing attempt.
Repeating `submit` with an existing idempotency key enters the same durable
reconciliation logic and never creates a second effect.

The gateway loads authority, review, budget and route grants only from:

```text
.moonsuite/products/moonclaw/capability-http-policy.json
```

The request cannot supply or widen that policy. The policy selects a
workspace-contained `flow/capability-catalog.json` (or another explicitly
configured workspace-relative catalog) and an exact operation/adapter route.
See
[`moonclaw-capability-http-policy.v1.json`](examples/moonclaw-capability-http-policy.v1.json)
and
[`capability-http-policy.schema.json`](../schemas/capability-http-policy.schema.json).

Two transports are available:

- `moonclaw.pack-tool-http.v1` calls an exact host-approved loopback
  pack-owned submit/reconcile adapter using `PackToolExecutionRequest`,
  `PackToolExecutionResult`, and `PackToolReconciliation`.
- `moonclaw.agent-goal-http.v1` wraps the existing MoonClaw native goal runtime
  through `moonclaw_agent_goal_http_transport`; it does not start a second
  runtime.

Transport URLs are host policy, are restricted to explicit loopback HTTP
targets, and cannot contain credentials, query strings, fragments, or traversal
segments (including percent-encoded traversal). A provider-bearing route
additionally needs its
`provider_route_ref` in `approved_provider_route_refs`; an invocation carrying
`provider_calls_forbidden: true` still blocks it. Authority denial, missing
routes, provider-route denial, and missing catalogs return typed HTTP errors
with the immutable request/attempt/idempotency identity.

Pack-adapter calls use the host timeout. A timeout, lost response, or
undecodable submit response is persisted as `unknown`, not terminal failure,
because the remote adapter may already have accepted the idempotency key. The
only next action is `/reconcile` with the same immutable invocation. An
explicit, decoded adapter `failed` result remains terminal.

Mutation requests require the exact loopback gateway `Host`. Browser requests
must also have an identical `Origin`, which means a product UI uses its
same-origin host proxy rather than cross-origin JavaScript. If gateway token
authentication is configured, these endpoints require the matching bearer
token. Server-to-server loopback requests may omit `Origin`.

## Durable result and restart behavior

Before calling the executor, MoonClaw writes:

```text
.moonsuite/products/moonclaw/capability-invocations/
  <sha256-of-idempotency-key>/result.json
```

The file is written under an exclusive per-attempt lock and starts in
`submitted`. Terminal receipts expose the exact fields consumed by MoonFlow's
`AdapterResult`, together with catalog, operation, schema and health lineage.
The file can therefore be passed directly to `moonflow reconcile-attempt`.

If MoonClaw restarts after submission but before terminal settlement, repeating
the invocation does not repeat the effect. It asks the same pack-owned adapter
to reconcile the idempotency key. Missing reconciliation produces `unknown`,
which requires investigation rather than an automatic retry.

Successful output artifacts must:

- remain workspace-relative after symlink resolution;
- exist at settlement time;
- stay inside a manifest-declared evidence prefix; and
- hash to the `output_digest` returned for MoonFlow reconciliation.

Agent success remains review-ready execution evidence, never product
acceptance.

The HTTP `status` route reads this same receipt under the per-attempt lock and
does not resolve or contact an execution route and does not require a current
authority grant. The caller still needs the exact invocation, loopback host,
and configured bearer token. Status therefore survives gateway restart,
adapter outage, route removal, or later grant revocation without permitting a
new effect.

## MoonFind host wiring

MoonFind's native host already sends the bare immutable invocation and consumes
the bare receipt. Point its generic ports at the gateway:

```sh
MOONCLAW_CAPABILITY_SUBMIT_URL=http://127.0.0.1:18123/v1/capability/submit
MOONCLAW_CAPABILITY_RECONCILE_URL=http://127.0.0.1:18123/v1/capability/reconcile
```

Its browser continues to call MoonFind's same-origin
`/api/v1/capability/submit` and `/reconcile` proxy. The MoonFind pack-owned
adapter must separately expose the two loopback `PackToolExecutionRequest`
ports named by the host policy. MoonClaw will not fabricate that adapter,
import MoonFind domain code, or treat its later Cowork model command as part of
capability preparation. If the pack adapter, active pack, health proof,
authority, or provider route is absent, the UI remains blocked with the exact
attempt available for status/reconciliation.

## Retired legacy boundary

`moonclaw flow-adapter` is retained as historical source and test evidence only.
Its CLI entry point is fail-closed and cannot execute, attest, or review product
work. This prevents the former generic external-product request format—and its
former MoonWiki product alias—from bypassing exact installed-pack, catalog,
authority, health, and reconciliation checks.

Do not add a product branch there. Product integration must publish a pack
tool/schema, adapter declaration, health evidence and pack-owned executor, then
enter MoonClaw through `execute_installed_capability_v1`.
