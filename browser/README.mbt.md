# Governed browser worker

This package owns MoonClaw's typed policy state for a browser session shared by
the user and an agent. It deliberately does not own presentation, authority,
durable evidence, or a browser process.

The worker binds every action to a session, workspace, book revision, code
revision, run, and authority envelope. It provides visible state transitions
for agent operation, pause, stop, user takeover, and return. Action budgets,
effect classes, redaction, target stability, and replay lineage fail closed.

`BrowserOperation` is the concrete page action verb. `BrowserEffectClass` maps
that verb to the portable constitutional effect class consumed by MoonGate and
MoonFlow. In particular, a navigation verb maps to external navigation and is
not part of the default local-preview authority.

The worker is two-phase. `prepare` validates policy and produces a typed host
command but no receipt. Only `complete`, after checking a host receipt's exact
session/action/revision/authority/capability identity and non-empty before/after
state digests, can accept the action. Page-authored diagnostics are untrusted.

Snapshots preserve remaining budget, control state, accepted/rejected receipts,
and duplicate guards across restart. Deterministic replay binds the next host
command to the accepted source receipt's before-state digest and fails on state
or semantic-target divergence.

The `process_host` package supplies the production executable boundary. Its
deterministic fixture exercises transport and state semantics but is not a real
browser or screenshot claim.
