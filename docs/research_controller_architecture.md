# Controller Profile Architecture

Date: 2026-03-19

## Goal

Define a generic way for MoonClaw to recognize and run controller-style jobs from JSON configuration, without baking domain policy into the runtime.

Research is one possible use case, but it should not define the core design.

## Current Direction

The runtime should be responsible for:

- loading JSON job profiles
- matching a request to a profile
- compiling a proposal into a normal workflow
- persisting controller state, iterations, lineage, and artifacts
- executing child jobs and recording their results

The runtime should not be responsible for:

- deciding the next hypothesis
- deciding whether to branch
- deciding whether to retry
- deciding domain-specific acceptance criteria
- embedding research-specific logic

Those decisions should come from declarative JSON policy plus normal AI step outputs.

## Core Split

- code owns generic execution and persistence
- JSON owns profile shape and controller policy
- AI owns contentful reasoning inside the allowed policy

In other words:

- runtime: "how to store and execute"
- profile: "what structure and policy apply"
- AI: "what to do next within that structure"

## Generic Profile Model

Profiles live in `moonclaw.json`:

```json
{
  "jobs": {
    "profiles": {
      "research_controller": {
        "family": "research_controller",
        "role": "controller",
        "priority": 100,
        "match": {
          "any": ["research", "papers", "arxiv", "benchmark"]
        },
        "steps": [
          {
            "id": "collect",
            "title": "Collect evidence",
            "kind": "job.delegate",
            "request_template": "Collect relevant evidence for ${request}"
          },
          {
            "id": "evaluate",
            "title": "Evaluate outputs",
            "kind": "job.analysis",
            "prompt_template": "Evaluate the collected outputs for ${proposal.title}"
          }
        ],
        "metadata": {
          "controller_policy": {
            "iteration_mode": "step_driven",
            "child_result_schema": "generic/evaluator_result.v1"
          }
        }
      }
    }
  }
}
```

The important part is that the runtime does not interpret `research_controller` specially. It just sees a profile with a controller role and some metadata.

## Generic Controller Records

The runtime can persist generic records such as:

- `JobControllerState`
- `JobControllerIteration`
- `JobControllerLineageEdge`

These are generic bookkeeping records. They should not encode domain semantics.

Examples of valid generic uses:

- top-level controller run state
- current active iterations
- accepted/rejected iterations
- parent-child iteration edges
- child job/run links

Examples of invalid core assumptions:

- a hardcoded "hypothesis" meaning only for research
- a hardcoded evaluator schema
- a hardcoded branch policy
- a hardcoded paper-fetch loop

## Recommended Next Design Step

The next important move is to make controller behavior more declarative.

Instead of adding more controller policy in MoonBit code, profiles should define a JSON policy block, for example:

```json
{
  "controller_policy": {
    "iteration_mode": "step_driven",
    "advance_on": ["step.completed"],
    "branching": "ai_decides",
    "acceptance_source": "child_output",
    "result_schema": "generic/evaluator_result.v1"
  }
}
```

The runtime would then:

- enforce event and storage mechanics
- validate required fields
- persist decisions and lineage

But it would not decide the policy itself.

## What To Keep

These parts of the recent implementation are still aligned with the generic goal:

- JSON-defined profile matching
- mechanical compilation from proposal to workflow
- controller state persistence
- iteration and lineage persistence
- child-run attachment to controller iterations

## What To Be Careful About

These are the main overreach risks:

- making default planning too elaborate
- growing controller semantics directly in runtime code
- making the architecture read as "research framework"
- treating profile families as hardcoded product categories

The current default generic plan should stay compact and execution-oriented unless a profile explicitly asks for more structure.

## Recommended Product Boundary

MoonClaw should be:

- a generic agent runtime
- a generic job/workflow executor
- a generic controller/child-job recorder

Higher-level systems should provide:

- research policy
- experiment policy
- review policy
- evaluation schemas
- branching rules

That keeps the project general while still allowing strong verticals on top.
