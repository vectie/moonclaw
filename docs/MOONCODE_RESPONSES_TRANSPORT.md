# MoonCode Responses transport trial

MoonCode can route planner rounds through MoonGate's OpenAI Responses
compatibility endpoint. The trial is additive and default-off: existing Chat
Completions behavior does not change unless the command payload explicitly
sets `planner_responses_transport` to `true`.

## Safety and privacy defaults

- MoonClaw accepts the Responses route only from a loopback MoonGate URL whose
  path contains `/openclaw/v1`. It never sends this trial directly to an
  arbitrary provider URL.
- MoonGate independently requires
  `MOONGATE_OPENCLAW_RESPONSES_ENABLED=true`; otherwise the route returns 404.
- Provider-side response storage is always false. MoonClaw omits
  `previous_response_id` and requests only current-turn reasoning context.
  Enabling upstream retention requires a separately reviewed data policy and
  explicit operator authority; it is not inferred from this transport flag.
- `planner_responses_chat_fallback` is also separate and defaults to false.
  When enabled, only a permanent HTTP incompatibility can fall back to Chat
  Completions. The fallback retains the complete request rather than the
  Responses continuation suffix.

## Command controls

| Payload field | Accepted values | Default |
| --- | --- | --- |
| `planner_responses_transport` | Boolean | `false` |
| `planner_responses_chat_fallback` | Boolean | `false` |
| `planner_prompt_cache_mode` | `implicit`, `explicit` | omitted |
| `planner_prompt_cache_ttl` | `30m`, `24h` | omitted |

The prompt-cache key is a stable session-scoped value. Invalid cache policy
strings are omitted rather than forwarded.

## Observability and rollout

Planner records use the existing `moonclaw.planner.metrics.v1` contract and add
the closed `model_transport` outcome (`responses`, `chat_completions`, or
`chat_fallback`) plus provider-reported `cache_write_tokens` when available.
MoonGate aggregates these as unlabeled low-cardinality counters. Response IDs,
cache keys, prompts, session IDs, paths, and tool arguments are never metric
labels.

Evaluate the transport with the paired offline harness replay before widening
traffic. Task success, verifier success, and safety recovery must remain equal
or improve before considering token, cache, or latency gains. Keep fallback as
an independent cohort so its effects remain measurable.
