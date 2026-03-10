# MoonClaw Gateway CLI

This README matches `cmd/gateway/main.mbt`.

## Implemented Commands

```bash
moonclaw gateway start [--port PORT] [--cwd DIR] [--home DIR]
moonclaw gateway connect [--url URL] [--token TOKEN]
moonclaw gateway agent --message "..." [--session KEY] [--cwd DIR] [--model NAME] [--wait] [--timeout MS]
moonclaw gateway health [--url URL] [--token TOKEN]
moonclaw gateway help
moonclaw gateway version
```

Not implemented in the CLI:

- `gateway status`
- `gateway stop`
- `--detach`

## Command Flow

```text
cmd/main/main.mbt
  -> ["gateway", ..rest]
  -> cmd/gateway/main.mbt::start(rest)
    -> start | connect | agent | health | help | version
```

The subcommand dispatch consumes the command correctly from `rest`; this was previously broken and is now fixed.

## `start`

```bash
moonclaw gateway start
moonclaw gateway start --port 19000
moonclaw gateway start --cwd /repo --home ~/.moonclaw
```

Flow:

```text
start_gateway
  -> Gateway::new(...)
  -> gateway.start()
```

## `connect`

```bash
moonclaw gateway connect
moonclaw gateway connect --url http://localhost:19000
```

Flow:

```text
connect_gateway
  -> gateway/client/Client::new(...)
  -> Client::connect()
  -> POST /v1/rpc method=connect
```

## `agent`

```bash
moonclaw gateway agent --message "review this code" --wait
moonclaw gateway agent --message "continue" --session repo-review --wait
moonclaw gateway agent --message "use another cwd" --cwd /repo --wait
```

Flow:

```text
run_agent
  -> Client::connect()
  -> Client::agent(...)
  -> optional Client::wait_agent(...)
```

## `health`

```bash
moonclaw gateway health
moonclaw gateway health --url http://localhost:19000
```

Flow:

```text
check_health
  -> Client::health()
  -> POST /v1/rpc method=health
```

## Gateway Features Behind the CLI

The CLI is just a thin front-end. The service behind it currently exposes:

- direct agent runs
- sessions
- SSE agent events
- channels and extensions
- Feishu webhook ingress
- mailboxes
- coordination tasks
- pipelines

See:

- `docs/gateway_usage.md`
- `docs/system_architecture.md`
- `docs/multi_agent_collaboration_design.md`
