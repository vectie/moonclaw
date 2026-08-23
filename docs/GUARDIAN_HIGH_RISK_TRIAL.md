# High-risk Guardian qualification trial

MoonClaw has a default-off shadow qualification phase enabled per command with
`payload.planner_guardian_high_risk_trial=true`. It runs only for tool calls
that the deterministic runtime already routes to operator approval. Read-only
and ordinary low-risk actions incur no extra work.

The `moonclaw.guardian-trial.v1` observation contains only closed action kind,
closed risk-signal names, signal count, and the invariant
`behavior_changed=false`. It never retains command text, arguments, paths,
user content, model-authored prose, or identifiers beyond the existing event
envelope. The qualifier performs no external inference and cannot allow, deny,
or bypass the existing operator decision.

This safely establishes high-risk cohort selection and privacy/cardinality
gates before introducing a model reviewer. A future model-backed phase must be
separately authorized and configure the exact provider, payload projection,
retention, timeout, and cost ceiling. Until then, `outcome=review_required`
means only that the existing operator review remains authoritative.
