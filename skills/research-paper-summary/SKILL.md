---
name: research-paper-summary
description: Summarize research papers or small paper sets with emphasis on problem, method, evidence, limitations, and practical relevance. Use when a workflow step needs a concise, grounded paper summary from parsed research artifacts.
---

# Research Paper Summary

Use this skill when summarizing one paper or a small set of closely related papers.

## Output shape

Produce these sections when possible:

- Problem
- Main idea
- Key method details
- Evidence and results
- Limitations
- Why it matters

## Rules

- Stay grounded in the provided paper text and metadata.
- Prefer precise claims over hype.
- Call out uncertainty when the paper text is incomplete.
- If multiple papers are present, separate shared themes from per-paper findings.
- Do not fabricate benchmarks, datasets, or numeric results.

## Good defaults

- Keep summaries compact and decision-oriented.
- Mention novelty only when you can compare it to obvious prior baselines in the text.
- End with 2-4 bullet takeaways if the caller asks for a digest.
