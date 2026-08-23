# Harness adversarial qualification

This qualification layer exercises malformed and boundary inputs without live
provider, browser, or tool calls. It complements the representative harness
cohorts and the anonymized baseline/variant replay. The tests are deterministic
and do not enable production feature flags.

## Coverage

| Surface | Qualification contract |
| --- | --- |
| Responses SSE | Truncated JSON, scalar and array payloads, missing or incorrectly typed fields, unknown events, malformed output items, terminal failures, Unicode deltas, and a 48-case typed-field mutation corpus are rejected or projected deterministically. Terminal error and `[DONE]` events never become successful completion. |
| Context provenance | Exact 64-character kind and 160-character source boundaries are accepted. Empty, oversized, whitespace, control, punctuation, CJK, and emoji tokens normalize conservatively without changing visible message bytes. |
| Deferred tool registry | Empty, control-bearing, Unicode, 256/257-character, and high-limit queries are deterministic and bounded. A receipt-forgery matrix mutates execution tool, acceptance, result tool, contract, limit, count, order, and declared names; no forged capability becomes loadable. |
| Active compaction | Three deterministic long-context seeds assert identical output and metrics, pressure reduction, valid provenance, and intact tool protocol. Orphaned results, late system instructions, invalid provenance, and unsupported developer messages fail closed with byte-identical source messages. |
| Output caps | Prefix and diagnostic head/tail caps are exercised at one-byte, marker, legacy 12,000-byte, and 50,000-byte boundaries with CJK, emoji, and combining characters. Output remains valid UTF-8, within the named byte budget, and retains exact source-byte accounting. |
| Replay distributions | A 140-case expansion provides 20 samples for every cohort and preserves deterministic p50/p95 results. One extreme sample outside p95 does not move the gate; two extreme samples do, proving sustained tail regression is detected without a hard wall-clock threshold. |

The Unicode boundary corpus found a production crash in prefix-only and
head/tail output truncation: a byte budget could split a multibyte UTF-8 code
point and abort in `String::sub`. Output capping now selects the largest valid
prefix or suffix within the budget. The regression test intentionally permits
fewer output bytes when the next complete code point does not fit.

## Run locally

Use isolated target directories:

```sh
moon test --target native --warn-list -all \
  --target-dir /tmp/moonclaw-qualification-openai \
  internal/openai/ai_responses_adversarial_wbtest.mbt

moon test --target native --warn-list -all \
  --target-dir /tmp/moonclaw-qualification-daemon \
  cmd/daemon/mooncode_harness_adversarial_qualification_wbtest.mbt

moon test --target native --warn-list -all \
  --target-dir /tmp/moonclaw-qualification-replay \
  internal/harness_replay/performance_distribution_wbtest.mbt
```

Then compile-check the affected packages and format the dedicated test files:

```sh
moon check --target native --warn-list -all \
  --target-dir /tmp/moonclaw-qualification-check \
  internal/openai internal/harness_replay cmd/daemon

moon fmt \
  internal/openai/ai_responses_adversarial_wbtest.mbt \
  internal/harness_replay/performance_distribution_wbtest.mbt \
  cmd/daemon/mooncode_harness_adversarial_qualification_wbtest.mbt
```

No test asserts a machine-local duration. Replay uses recorded distributions,
and in-process property corpora assert determinism, invariants, and bounded
output. Rollout interpretation remains quality first: task success, verifier
success, and safety/recovery must pass before cost/cache and latency
distributions are considered.
