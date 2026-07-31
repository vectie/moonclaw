# Child-agent delegation

MoonClaw continues to use its existing `job.delegate` child-run path. The
`moonclaw.child-delegation.v1` record narrows and binds that path; it is not a
new scheduler, workflow engine, or agent runtime.

A delegation binds exact parent and child run ids, parent and child principals,
allowed operation refs, artifact prefixes, maximum claim class, metered budget
ceilings, fresh child-bound authority, issue/expiry times, and an optional
parent delegation digest. Nested delegation can only narrow scope, budget,
lifetime, and claim class.

Runtime child principals must be `Agent`; the parent must be an `Agent` or
`Service`. Human principals cannot masquerade as runtime children. A child can
produce evidence, drafts, or reviewable output, but never final acceptance or
publication authority.

Before execution, a host calls `bind_child_run_execution_request_v1` with the
existing `ChildRunExecutionRequest`. Parent/child lineage must match exactly.
Authorization also requires a `ChildDelegationConsumptionV1` containing
accumulated and requested cost (micro-USD), runtime milliseconds, tokens, and
artifact count plus immutable metering evidence. Every budgeted dimension must
be present and remain under its ceiling; unverifiable or over-budget use is
denied. The returned governed request carries a digest-bound use receipt.
