# Research Job Test Guide

This is a concrete way to test whether MoonClaw can handle a real research-style controller job.

## 1. Install the example profile

Copy [research_job_moonclaw.json](/Users/kq/Workspace/moonclaw/docs/examples/research_job_moonclaw.json) into the workspace you will run the gateway against as `moonclaw.json`.

If you want to merge it into an existing config, copy only the `jobs.profiles.topic_watch_controller` block.

## 2. Start the gateway in an isolated workspace

```bash
mkdir -p ~/.moonclaw/workspace
cp /Users/kq/Workspace/moonclaw/docs/examples/research_job_moonclaw.json ~/.moonclaw/workspace/moonclaw.json
moon run cmd/main -- gateway start --home ~/.moonclaw --cwd ~/.moonclaw/workspace
```

## 3. Trigger a real research-style job

Use Feishu, the gateway chat surface, or the UI chat entry and send:

```text
/plan-job Research recent Vision-Language-Action papers on arXiv, identify the most relevant directions, and produce a short topic watch brief.
```

Then confirm it:

```text
/confirm <proposal_id>
```

## 4. What success looks like

You should see:

- the proposal family become `topic_watch_controller`
- a controller-shaped job definition rather than a plain generic proposal job
- compact controller steps: `collect`, `rank`, `report`
- normal run status via `/job-status`
- controller state persisted for the run
- if a step emits a controller decision, a persisted controller decision and optional next iteration

## 5. How to judge the system's ability

Use these checks:

1. Profile matching
   The request should match the JSON profile without code changes.

2. Plan quality
   The plan should stay compact and research-shaped without expanding into a hardcoded 5-step generic workflow.

3. Execution continuity
   The confirmed run should execute as a normal job and remain inspectable with `/job-status`.

4. Controller recording
   The run should persist controller state, step iterations, lineage edges, and any controller decisions.

5. Output quality
   The final brief should be grounded, ranked, and concise rather than generic filler.

6. Flexibility
   If you revise the profile JSON, behavior should change without touching MoonBit code.

## 6. Failure modes to look for

These indicate the system is still too rigid:

- the request matches no profile even though the terms are obvious
- the runtime falls back to a generic workflow unexpectedly
- controller decisions only work for one exact JSON shape
- the system cannot branch or record next iterations from step output
- changing profile metadata has no effect on runtime behavior

## 7. A stronger follow-up test

After the first run works, change the example profile:

- rename a verdict alias
- rename a `next_iteration_fields` mapping
- adjust the step prompts

Then rerun the same research task.

If MoonClaw adapts without code changes, that is the core signal that the controller behavior is genuinely JSON-driven rather than hardcoded.
