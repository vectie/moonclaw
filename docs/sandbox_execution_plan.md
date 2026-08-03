# Sandbox Execution Plan

## Goal

Add a command-execution control layer that starts with two practical features:

- simulate command execution before running it
- require explicit approval for risky commands

Then grow that layer into a fuller enterprise sandbox with policy, auditing, and
enforcement.

## Why this belongs in the current architecture

MoonClaw already has two useful ingredients:

- a `SecurityRuntime` that persists approvals and command policy
- centralized process-launch paths in `internal/spawn/manager.mbt`,
  `job/manager.mbt`, `acp/runner.mbt`, and `gateway/server/acp_methods.mbt`

The current gap is that approvals are attached to a few named actions, while
actual shell/process execution remains mostly direct. The sandbox feature should
bridge those two layers instead of adding another parallel control system.

## Current execution surfaces

### Existing approval primitives

- `security/runtime.mbt`
  - approval records
  - scope keys
  - `/approve`
  - command policy toggles like `commands.native`

### Existing execution sites

- `internal/spawn/manager.mbt`
  - low-level process launch queue
- `job/manager.mbt`
  - shell-style `sh -c <command>` execution
- `acp/runner.mbt`
  - external ACP backend process launch
- `gateway/server/acp_methods.mbt`
  - managed ACP process launch

These are the main seams for inserting preflight analysis, simulation, and
approval checks.

## Product shape

### Phase 1: Preflight simulation

Add a preflight layer that evaluates a command request before launch and returns
structured analysis:

- normalized command and arguments
- cwd and workspace
- command kind
  - direct binary
  - shell string
  - script runner
- risk level
  - low
  - medium
  - high
  - blocked
- risk reasons
  - writes outside workspace
  - destructive shell pattern
  - networked install
  - privilege escalation
  - unknown shell string
- predicted effects
  - read files
  - write files
  - network access
  - process fan-out

The first release does not need perfect syscall-level truth. It only needs
deterministic, explainable classification.

### Phase 2: Approval gate for risky commands

Use the existing approval runtime to require approval when preflight marks a
command as `high` risk or `blocked unless approved`.

Behavior:

- low-risk commands run immediately
- medium-risk commands run immediately but log a warning
- high-risk commands create a pending approval
- blocked commands do not run unless policy explicitly permits them

Approval records should become command-aware:

- action kind: `command.execute`
- action target: stable command fingerprint, not raw free text only
- scope key: existing channel/session scope key
- preview: rendered command, cwd, risk reasons

### Phase 3: Enterprise sandbox foundation

Once the preflight and approval path exists, add stronger policy and
enforcement:

- per-channel and per-agent sandbox policy
- allowlists and denylists
- workspace boundary enforcement
- optional network policy
- audit log of requested vs approved vs executed command
- policy bundles for teams and tenants
- approval expiry and dual-approval rules
- non-interactive service accounts with stricter defaults

This should remain an extension of the same execution-control model, not a
separate subsystem.

## Proposed core types

### `security/command_policy.mbt`

Introduce explicit policy types instead of relying on string toggles alone:

- `SandboxMode`
  - `Off`
  - `Simulate`
  - `ApproveRisky`
  - `Enforce`
- `RiskLevel`
  - `Low`
  - `Medium`
  - `High`
  - `Blocked`
- `CommandIntent`
  - binary
  - shell
  - script runner
  - package manager
  - vcs
  - unknown
- `CommandAssessment`
  - normalized command
  - args
  - cwd
  - workspace
  - risk level
  - reasons
  - predicted effects
  - requires approval
  - allowed by policy

Keep the old `commands.native` config as a compatibility shim, but map it onto
the newer policy shape.

### `security/command_preflight.mbt`

Mechanical command analysis:

- normalize commands
- detect shell wrappers
- classify common dangerous patterns
- compare paths against workspace/home boundaries
- produce `CommandAssessment`

This module should be pure and test-heavy.

### `security/command_gate.mbt`

Decision layer:

- take `CommandAssessment`
- apply configured policy
- decide:
  - allow
  - require approval
  - deny
- generate approval payloads and operator-facing text

## Integration plan

### Step 1

Wrap `job/manager.mbt` with preflight assessment before `sh -c`.

Why first:

- it is the highest-risk path because it accepts shell strings directly
- it is the easiest place to prove the product behavior

### Step 2

Wrap `internal/spawn/manager.mbt` with an optional assessed-launch API:

- existing spawn path stays available for internal low-level callers
- new path accepts workspace, policy context, and approval scope

This becomes the reusable primitive for future rollout.

### Step 3

Move ACP process launch onto the same gate:

- `acp/runner.mbt`
- `gateway/server/acp_methods.mbt`

ACP should not invent its own approval semantics.

### Step 4

Expose the feature in operator interfaces:

- chat replies explaining why a command was held
- `/approvals` already exists and can be reused
- operator UI can show:
  - command preview
  - risk level
  - reasons
  - approval token/state

## Config direction

Add config under `commands` or a new `sandbox` section.

Short-term compatible shape:

```json
{
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "sandboxMode": "approve-risky",
    "defaultPolicy": "workspace-safe"
  }
}
```

Longer-term enterprise shape:

```json
{
  "sandbox": {
    "mode": "enforce",
    "workspaceBoundary": "strict",
    "network": "deny",
    "approval": {
      "highRisk": true,
      "expiryMinutes": 15
    },
    "allow": {
      "commands": ["git", "ls", "cat", "rg", "moon"],
      "paths": ["/workspace"]
    },
    "deny": {
      "patterns": ["rm -rf /", "curl | sh"]
    }
  }
}
```

## First implementation slice

The first slice should stay narrow:

1. Add `CommandAssessment` and a pure preflight classifier.
2. Gate `job/manager.mbt` shell commands behind it.
3. Reuse `SecurityRuntime` approvals for high-risk commands.
4. Add readable command-hold messages in gateway chat.
5. Add tests for:
   - safe read-only command
   - risky destructive shell command
   - approval request generation
   - approval consume then execute

This is enough to prove the product.

## Non-goals for the first slice

- container sandboxing
- kernel syscall interception
- full path taint tracking
- perfect shell parsing
- enterprise RBAC
- per-tenant approval delegation

Those belong to later phases.

## Open questions

- Should approval target the exact raw command string, or a normalized command
  fingerprint?
- Should approval be one-shot or reusable within a short TTL?
- Should ACP backend launches be exempt from some checks, or treated exactly
  like any other external process?
- Should simulation mode be exposed as a user command such as `/simulate <cmd>`?
- Do we want policy attached to channel, workspace, agent, or all three?

## Recommendation

Build this as a single execution-governance path:

- preflight
- assess risk
- request approval if needed
- execute with audit trail

Do not split "simulation", "approval", and "enterprise sandbox" into separate
systems. The enterprise version should be the stricter continuation of the same
pipeline.
