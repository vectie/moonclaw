# Offline harness baseline replay

MoonClaw can compare a candidate harness against a baseline from paired,
anonymized observations without invoking a model, browser, tool provider, or
other external service. The replay is deterministic and intended for local
development, CI, and rollout review.

The shipped fixture covers two paired observations for each required cohort:

- read-only inspection;
- generic edit;
- MoonBit validation;
- UI/browser work;
- delegated workers;
- long-context follow-up;
- failure and retry.

Each case contains only an anonymized case identifier, a closed cohort, and
aggregate baseline/variant observations. Raw prompts, paths, session IDs, tool
arguments, and outputs are rejected. Duplicate case identifiers are rejected,
and every cohort must meet the fixture's explicit minimum sample count.

## Run

```sh
moon run --target native \
  --target-dir /tmp/moonclaw-harness-replay \
  cmd/harness_replay -- \
  testdata/harness_replay/anonymized_cases.json
```

Exit status is `0` when every cohort passes, `1` when a valid replay fails a
rollout gate, and `2` when the input cannot be read, parsed, or validated. The
report contract is `moonclaw.harness-replay-report.v1`.

Focused validation:

```sh
moon test --target native \
  --target-dir /tmp/moonclaw-harness-replay-test \
  internal/harness_replay

moon check --target native --warn-list +73 \
  --target-dir /tmp/moonclaw-harness-replay-check \
  internal/harness_replay cmd/harness_replay
```

## Quality-first gates

For every cohort, replay evaluates gates in this order:

1. task-success count does not regress;
2. verifier-success count does not regress;
3. safety/recovery-success count does not regress;
4. fresh-input-token p95, request-character p95, and aggregate cache-read ratio
   stay within the fixture's cost/cache policy;
5. latency p50 and p95 stay within the fixture's latency policy.

The first failed gate is retained in both the cohort and top-level report. A
cheaper or faster variant cannot compensate for a task, verifier, or recovery
regression. Cohorts are never averaged together, and a missing or undersampled
cohort fails with `sample_count` before its performance gates are considered.

Thresholds are fixture data expressed in parts per million; there are no
hidden wall-clock constants. This makes recorded distributions reproducible
and avoids flaky machine-speed assertions. The example policy permits 5% cost
regression, a two-percentage-point cache-ratio drop, and 10% p50/p95 latency
regression after the quality gates pass.

Percentiles use deterministic nearest-rank selection. With two samples, p50 is
the lower ordered value and p95 is the higher ordered value. Production rollout
reviews should use a materially larger per-cohort sample count while preserving
the same contract and evaluation order.

The deterministic qualification suite expands the shipped observations to 20
samples per cohort and verifies tail behavior explicitly: with 20 observations,
one maximum outlier remains outside p95, while two maximum outliers move p95 and
fail the latency gate. See
[HARNESS_ADVERSARIAL_QUALIFICATION.md](HARNESS_ADVERSARIAL_QUALIFICATION.md).

## Observation and phase contracts

Each baseline and variant observation records:

- task, verifier, and safety/recovery success booleans;
- prompt tokens, cache-read tokens, request characters, and fresh-input tokens
  derived by replay;
- latency, retry count, and a closed outcome (`selected`, `no_tool_calls`,
  `recovered`, or `failed`);
- `moonclaw.harness-phase-metrics.v1` phase timings.

The phase contract contains nonnegative `queue_ms`, `request_build_ms`,
`provider_ms`, `tool_execution_ms`, `verification_ms`, and `total_ms`. A named
phase cannot exceed total latency, and `total_ms` must equal the observation's
latency. Named phases may overlap, so their sum is not required to equal total.
Reports retain deterministic p50/p95 distributions for every phase.

The replay package does not change planner behavior or emit live metrics. To
build a trial fixture, pair baseline and variant observations for the same
anonymized case, strip all content-bearing fields before storage, set explicit
policy values, and review sample counts before using the result as a rollout
gate.
