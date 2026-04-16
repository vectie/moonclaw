---
name: provider-task-repair
description: Repair an invalid provider task output into the exact ProviderTaskResult shape. Use when provider execution returned prose, planning output, or malformed JSON.
---

# Provider Task Repair

Use this skill only to convert a bad provider-task output into the required runtime result object.

## Rules

- Return JSON only.
- Do not return plans, outlines, commentary, or markdown fences.
- Preserve the underlying result as much as possible.
- If the previous output is planner-shaped, collapse it into one result for the current task.
- Do not invent unrelated artifacts or durable updates.
- If the original output did not complete real work, produce a concrete blocker-style summary instead of a fake success.

## Output discipline

- Follow the exact ProviderTaskResult contract supplied by MoonClaw.
