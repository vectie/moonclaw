---
name: research-novelty-review
description: Evaluate the novelty and significance of research papers using grounded comparisons, method changes, and evidence quality. Use when a workflow step needs novelty assessment rather than a plain summary.
---

# Research Novelty Review

Use this skill for novelty-focused analysis of one paper or a small paper batch.

## Evaluate

- What changed relative to common prior approaches
- Whether the change is conceptual, architectural, data-related, or evaluation-related
- Whether the evidence supports the claimed novelty
- Whether the contribution seems incremental, meaningful, or potentially overstated

## Output shape

- Claimed novelty
- Likely real novelty
- Evidence supporting novelty
- Evidence weakening the claim
- Overall significance

## Rules

- Be skeptical of broad “first” or “state-of-the-art” claims.
- Distinguish novelty from good engineering.
- Distinguish novelty from scale-only improvements.
- If prior-work context is weak, say so explicitly instead of overclaiming.
