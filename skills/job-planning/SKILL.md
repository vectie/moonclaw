---
name: job-planning
description: Draft safe MoonClaw job proposals with the exact proposal JSON schema and execution-oriented step decomposition. Use when planning or repairing a job proposal.
---

# Job Planning

Use this skill when MoonClaw needs to draft or repair a job proposal.

## Output contract

Return JSON only.

Use exactly this top-level shape:

```json
{
  "title": "string",
  "summary": "string",
  "tags": ["string"],
  "steps": [
    {
      "id": "string",
      "title": "string",
      "prompt": "string",
      "kind": "string"
    }
  ]
}
```

## Forbidden aliases

Do not invent or rename the contract fields.

Do not use aliases such as:

- `plan`
- `draft_plan`
- `job`
- `request_text`
- `overview`
- `step`
- `details`
- `objective`

## Planning rules

- Never execute the job.
- Produce a draft that is safe to confirm later.
- Prefer the smallest sufficient number of steps, but do not collapse non-trivial work into one generic execute step.
- For analytical, business, estimation, due-diligence, or report-oriented work, produce 4 to 8 concrete phases unless the request is obviously trivial.
- Each step must describe a real deliverable, not filler.
- Step titles should be short and human-readable.
- Step prompts should tell the step exactly what to produce.
- Use kind `job.analysis` unless a better existing workflow step kind is clearly required.

## Repair rules

- If the previous output used the wrong shape, rewrite it into the exact schema above.
- If the previous output returned a single generic execute step for a non-trivial request, decompose it into concrete phases.
- Preserve the user’s intent while fixing the structure.
