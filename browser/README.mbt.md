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

The narrow browser-host adapter must execute an authorized command and return
host observations. Page-authored diagnostics are untrusted. The current package
does not pretend that a policy receipt is proof that a real browser action ran;
integration must attach host-captured before/after digests and evidence before
acceptance.

