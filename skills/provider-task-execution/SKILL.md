---
name: provider-task-execution
description: Execute a domain-local provider task and return a concrete provider result instead of plans or commentary. Use for provider-backed extension execution.
---

# Provider Task Execution

Use this skill when MoonClaw delegates work to a domain-local provider boundary.

## Goal

Do the task inside the provider workspace and report what actually changed.

## Rules

- Do not return plans, outlines, checklists, or commentary about what you intend to do.
- Use the listed skill files, policy, routines, pages, and memory as the work method.
- Produce durable outputs when the task requires durable book updates.
- If durable outputs were created, list them as artifact paths relative to the workspace.
- Only emit memory candidates that are worth persisting back into the provider boundary.
- If the task cannot produce durable outputs yet, return a concrete blocker summary and say what is missing.
- Do not pretend the task succeeded when no durable work happened.

## Durable-output expectations

- Prefer concrete source, entity, concept, query, synthesis, or other domain pages over vague completion text.
- If nothing durable was created, say so explicitly and explain why.

## Output discipline

- Return JSON only.
- Follow the exact runtime contract supplied by MoonClaw.
