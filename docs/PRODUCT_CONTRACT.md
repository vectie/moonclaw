# MoonClaw product contract

Class: platform
Maturity: advanced local alpha
Last reviewed: 2026-07-30

## Outcome

MoonClaw is MoonSuite's sole agent runtime. It turns an approved request into a
durable session or job, runs the model/tool loop, and records events, artifacts,
control decisions and memory.

## Users and jobs

- Operators run, inspect, steer, cancel and recover agent work.
- MoonDesk submits commands and renders the resulting journals.
- MoonFlow invokes MoonClaw when a declared work item requires agent execution.
- Domain packs expose tools to MoonClaw without adding another agent runtime.

## Ownership

MoonClaw owns model reasoning lifecycle, agent sessions, jobs, tool execution,
MoonCode runtime behavior, runtime memory and ACP remote-agent control.

MoonClaw does not own:

- domain ranking, media-production, robotics or accounting policy;
- durable dependency orchestration owned by MoonFlow;
- accepted book truth and Bookkeeper learning owned by MoonBook;
- provider policy and usage control owned by MoonGate;
- human acceptance or physical authority.

## Capability status

| Capability | Status |
| --- | --- |
| Native agent, job, tool and memory runtime | available |
| Durable journals, workspaces and artifact evidence | available |
| MoonCode command, control and evaluation paths | available |
| ACP remote-agent coordination | available |
| Gateway and operator surfaces | available locally |
| Versioned pack capability invocation and reconciliation | available |
| Live pack tool execution | conditional on an installed, healthy, conformant adapter |
| Autonomous product/domain policy | excluded |
| Production multi-user deployment | planned |

## Authority and evidence

Every consequential operation must carry the requested authority and produce a
receipt. Unknown outcomes reconcile before retry. Workspace artifacts remain
contained under the selected product/book roots. A successful runtime turn is
execution evidence, not acceptance evidence; named review remains outside the
runtime.

Domain-specific endpoints must not be added to MoonClaw. A MoonRobo action, for
example, is invoked through a MoonRobo-owned adapter while MoonClaw remains the
generic runtime.

The executable cross-product contract is documented in
[Generic Capability Invocation](CAPABILITY_INVOCATION.md). MoonClaw accepts
only canonical `<product>/<tool>@<pack-version>` operations and versioned
schemas from MoonFlow's compiled capability catalog. It then re-verifies the
active pack and expiring health evidence before execution.

## Operation

The canonical command and daemon surfaces are documented in the root README and
`cmd/`. Deployment-specific credentials remain host secret references.
Operators must back up durable product state and book-owned accepted artifacts,
not `_build` or disposable caches.

## Verification

Use the repository's targeted tests during development and the full native
suite before release:

```sh
moon check --target native
moon test --target native
moon info
moon fmt
```

## Release gates and next milestones

- Clean-machine daemon install, update, rollback and recovery proof.
- Multi-day restart/soak evidence without journal loss or duplicate effects.
- Capability-registry conformance and live health evidence for every pack
  adapter.
- Removal of stale domain-specific documentation and endpoints.
- Clear operator backup, restore and incident-response procedures.
