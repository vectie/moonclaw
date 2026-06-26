# MoonClaw Robot Routine Gateway

MoonClaw owns robot routine selection. Moonrobo owns physical-world context,
gateway ingress, task evidence, and MoonBook/RoboBook memory projection. The
gateway robot-routine endpoints make that boundary available as a service.

The same ownership is visible in MoonClaw's job/profile substrate through the
built-in `robot_routine` profile. That profile has `role: "robot"` and a single
`robot.routine.run` step targeting `POST /v1/robot/routine/run`, so robot work is
the third MoonClaw lane beside coding and general task work. A temporary
initiator, Rabbita, or an operator can initiate the lane during bring-up; the AI
decision and route selection still happen in MoonClaw, not in the initiator.

## Endpoints

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
`vectie/moonclaw/robot_routine`, and returns a multi-step routine plan plus
invocation status. The durable `/run` endpoint also persists the selected plan,
invocation result when present, stopped status, Moonrobo URL, and run path on
the MoonClaw side. Conflict responses from `/run` include the persisted `run`
object beside the error.

When the selected Moonrobo route requires a body, MoonClaw authors that body
from Moonrobo context instead of asking Moonrobo to infer routine decisions. In particular,
`/api/moonrobo/gateway/command` receives a concrete MoonClaw-authored command
body built from the latest `task_intent` goal, robot id, and timestamp.
`/api/moonrobo/proof-session` receives a bounded proof-session request with a
task message derived from the same durable task intent. Moonrobo only accepts,
gates, persists, and projects the result.

MoonClaw only selects Moonrobo routes that appear in
`context.tool_registry.providers[].capabilities[]` with the same HTTP method and
without physical execution authority. Concrete routes may match registered
templates such as `/api/replays/{session_id}/annotations`. If Moonrobo context
points at an unregistered route, the routine plan becomes an operator-owned
registry blocker at `/api/tools/registry` instead of invoking it.

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
