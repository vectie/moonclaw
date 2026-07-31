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

## Retired legacy boundary

`moonclaw flow-adapter` is retained as historical source and test evidence only.
Its CLI entry point is fail-closed and cannot execute, attest, or review product
work. This prevents the former generic external-product request format—and its
former MoonWiki product alias—from bypassing exact installed-pack, catalog,
authority, health, and reconciliation checks.

Do not add a product branch there. Product integration must publish a pack
tool/schema, adapter declaration, health evidence and pack-owned executor, then
enter MoonClaw through `execute_installed_capability_v1`.
