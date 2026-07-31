# MoonClaw runtime uninstall contract

Uninstalling or upgrading the MoonClaw runtime pack must preserve user-owned
workspace content and all durable execution evidence, including:

- `.moonsuite/products/moonclaw/capability-invocations/`;
- `.moonsuite/products/moonclaw/agent-goal-receipts/`;
- `.moonsuite/products/moonclaw/mooncode/sessions/`;
- accepted artifacts, review receipts and journals referenced by those records.

Runtime binaries, generated caches and renewable health attestations may be
removed. Evidence may be migrated only by a versioned, replayable migration
that retains old record identities and digests.
