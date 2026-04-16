---
name: analysis-adaptation
description: Judge whether an analysis step is complete, blocked on external input, or should expand into a child subplan. Use for adaptive followup, subplan fill, and missing-input extraction.
---

# Analysis Adaptation

Use this skill after an analysis step returns a first-pass result and MoonClaw must decide whether to complete, wait, or decompose.

## Core rule

Be conservative about calling a step completed.

If the output is mainly a blocker report, a request for more information, a screening-only answer, or a list of next actions, it is not complete.

## Verdict meanings

- `completed`: the step already delivered a usable result
- `needs_input`: meaningful progress is blocked until the user or an external source provides missing facts
- `needs_subplan`: useful work can continue now by splitting the task into smaller executable units

## Completion rules

- Choose `completed` when the current output already gives a usable deliverable.
- If operator resume guidance explicitly allows assumptions or best-effort guessing, do not downgrade a usable assumption-based deliverable to `needs_input`.
- If the output contains caveats but still gives a decision-useful result, keep it as `completed`.

## Missing-input rules

- Use `needs_input` only when missing facts truly block all meaningful completion.
- Missing inputs should be concrete facts, files, numbers, locations, assumptions, or external records.
- Do not ask the user to infer what is missing. State the missing items explicitly.

## Subplan rules

- Prefer `needs_subplan` over `needs_input` when useful preparation can still continue.
- Use `needs_subplan` for research, verification, checklist, template, comparison, extraction, or synthesis tasks that can make progress now.
- Do not default to subplanning. Only use it when decomposition materially improves execution.
- Suggested child tasks should be concrete and executable, not vague planning language.

## Output discipline

- Return JSON only.
- Use the exact verdict-specific shape required by the runtime.
