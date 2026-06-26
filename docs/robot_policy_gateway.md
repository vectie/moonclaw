# MoonClaw Robot Policy Gateway

MoonClaw owns robot routine policy. Moonrobo owns physical-world context,
gateway ingress, task evidence, and MoonBook/RoboBook memory projection. The
gateway robot-policy endpoints make that boundary available as a service.

## Endpoints

`POST /v1/robot/policy` selects the next Moonrobo route without invoking it.

`POST /v1/robot/policy/invoke` selects the route and invokes it only when the
decision is MoonClaw-owned, route-selected, and not physical-execution enabled.

Both endpoints accept:

```json
{
  "moonrobo_url": "http://127.0.0.1:5192",
  "now_ms": 1782454687052
}
```

`now_ms` is optional. The gateway fetches
`{moonrobo_url}/api/moonclaw/context`, passes the context to
`vectie/moonclaw/robot_policy`, and returns the policy decision plus invocation
status.

Moonrobo should not host this selection logic. If Moonrobo contains code with
agent-facing names, it should remain declarative projection code: context,
readiness, tool registry, task ingress, receipts, and durable memory. Planning,
selection, retry, and tool invocation belong in MoonClaw.
