# MoonClaw Robot Policy Gateway

MoonClaw owns robot routine policy. Moonrobo owns physical-world context,
gateway ingress, task evidence, and MoonBook/RoboBook memory projection. The
gateway robot-policy endpoints make that boundary available as a service.

## Endpoints

`POST /v1/robot/policy` selects the next Moonrobo route without invoking it.

`POST /v1/robot/policy/invoke` selects the route and invokes it only when the
decision is MoonClaw-owned, route-selected, and not physical-execution enabled.

`POST /v1/robot/routine` returns the ordered MoonClaw robot routine plan for the
current Moonrobo context. The plan includes runtime validation, gateway command,
proof session, physical feedback, and MoonBook memory steps as separate routine
steps.

`POST /v1/robot/routine/invoke` plans the routine and invokes only the next safe
MoonClaw-owned step. It does not invoke physical-execution-enabled steps; those
still require an explicit safety-gated execution path.

`POST /v1/robot/routine/run` is the durable closed-loop entrypoint. It plans the
routine, invokes the next safe MoonClaw-owned step when one is available, and
writes the run record under MoonClaw's `.moonclaw/robot-routine-runs/` ledger.
Idle plans, operator-owned blockers, and physical-execution blocks are persisted
before the endpoint returns its non-2xx response, so failed progress still leaves
durable evidence.

`GET /v1/robot/routine/runs` lists persisted robot routine runs. `GET
/v1/robot/routine/runs/{run_id}` returns one run record.

The POST endpoints accept:

```json
{
  "moonrobo_url": "http://127.0.0.1:5192",
  "now_ms": 1782454687052
}
```

`now_ms` is optional. The gateway fetches
`{moonrobo_url}/api/moonclaw/context`, passes the context to
`vectie/moonclaw/robot_policy`, and returns either a single policy decision or a
multi-step routine plan plus invocation status. The durable `/run` endpoint also
persists the selected plan, invocation result when present, stopped status,
Moonrobo URL, and run path on the MoonClaw side. Conflict responses from `/run`
include the persisted `run` object beside the error.

Moonrobo should not host this selection logic. If Moonrobo contains code with
agent-facing names, it should remain declarative projection code: context,
readiness, tool registry, task ingress, receipts, and durable memory. Planning,
selection, retry, and tool invocation belong in MoonClaw.

Moonrobo can still expose `/api/moonclaw/context` and compatibility projections
named for MoonClaw, but those projections are platform facts, not an agent. The
closed loop is:

1. Moonrobo publishes the digital/physical state, robot capabilities, live
   readiness, RoboBook paths, and safe command/proof endpoints.
2. MoonClaw reads that context through the robot routine endpoint.
3. MoonClaw selects the next step and records that turn in its robot routine run
   ledger, whether it invokes a non-physical step or stops at an idle/operator
   blocker.
4. Moonrobo persists command receipts, proof sessions, feedback, and MoonBook
   memory.
5. MoonClaw reads the updated context and repeats.
