# Long-context compaction lifecycle

MoonClaw has an opt-in active compaction lifecycle for very long MoonCode
planner runs. It changes only the provider-facing projection. The durable
command, execution journal, tool results, checkpoints, and user-visible
artifacts are not rewritten.

Active compaction is disabled by default:

```json
{
  "payload": {
    "planner_hybrid_semantic_compaction_active": true,
    "planner_context_window_tokens": 128000
  }
}
```

Both fields are required for activation. An unknown context window fails
closed. The separate `planner_hybrid_semantic_compaction_trial` flag remains a
shadow-only observation and never changes provider messages.

## Lifecycle

For flag-off requests, MoonClaw retains the existing compatibility behavior:
after 32 follow-up messages it uses the legacy bounded suffix projection. This
path is byte-for-byte unchanged.

For active requests, MoonClaw retains the current provider projection until
both conditions hold:

- the very-long-task threshold is reached (96 messages by default, bounded to
  64–512 with `planner_semantic_compaction_message_threshold`);
- measured context pressure reaches 75% by default (bounded to 60–90% with
  `planner_semantic_compaction_pressure_threshold_ppm`).

Provider-reported prompt tokens from the preceding round are preferred.
Serialized visible-message characters divided by four are the deterministic
fallback. Internal provenance metadata is excluded from both calculations.

Once eligible, the existing context compiler targets 50% pressure by default.
The target is explicit and configurable with
`planner_semantic_compaction_target_pressure_ppm`, bounded to 30–70% and kept
at least ten percentage points below the trigger. Old tool outputs are reduced
first; if needed, an old coherent history span is replaced by a deterministic
checkpoint while retaining the protected instruction/task prefix and newest
complete exchange.

## Safety invariants

The active projection is accepted only when all of these remain true:

- system and developer instructions are byte-identical and in the same order;
- no system/developer instruction appears after conversation turns begin;
- every retained tool result answers one unique immediately preceding
  assistant tool call, with no orphan, duplicate, or incomplete batch;
- every projected message carries valid `_moonclaw_context` provenance;
- the projection produces a deterministic character reduction.

Unsupported message roles, invalid provenance, malformed tool transcripts,
late instructions, compiler errors, or invariant mismatches return the exact
uncompacted input with a closed refusal reason. Developer-role messages are
therefore preserved even though the current Chat Completions parameter type
does not compile that role. Newly generated context checkpoints are tagged as
environment context; retained and redacted tool results keep their originating
tool-result provenance through call-ID alignment.

## Metrics

Each follow-up plan records `moonclaw.semantic-compaction-lifecycle.v1` with:

- `enabled`, `eligible`, `applied`, `reason`, and `invariants_preserved`;
- pressure source, context window, estimated/observed tokens, trigger, target,
  and target token budget;
- before/after message counts, visible serialized characters, and token counts;
- deterministic character reduction, redacted tool-result count, compacted
  message count, and whether the target budget was reached.

The metrics contain no prompt content, paths, session identifiers, tool
arguments, or outputs. An applied minimum safe projection may still report
`within_budget=false` when the immutable prefix plus newest complete exchange
cannot fit the requested target; the provider retains the safest deterministic
projection and normal provider error/retry handling remains authoritative.

## Why the active path bypasses the legacy 32-message projection

The original shadow trial required at least 96 messages, while the compatibility
follow-up builder compacted at 32. In normal runs the shadow threshold was
therefore unreachable after the first legacy projection. Active mode bypasses
that early projection only while its explicit flag is enabled, allowing actual
pressure to drive the lifecycle. The default compatibility path is unchanged,
and tests lock both behaviors.

## Focused validation

```sh
moon test --target native \
  --target-dir /tmp/moonclaw-semantic-lifecycle \
  cmd/daemon/mooncode_semantic_compaction_lifecycle_wbtest.mbt \
  cmd/daemon/mooncode_semantic_compaction_trial_wbtest.mbt \
  cmd/daemon/mooncode_context_provenance_wbtest.mbt

moon check --target native --warn-list +73 \
  --target-dir /tmp/moonclaw-semantic-lifecycle-check \
  cmd/daemon
```
