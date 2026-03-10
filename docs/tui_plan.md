# MoonClaw TUI Implementation

This document replaces the earlier plan-oriented draft and describes the current TUI behavior.

## Entry Point

File:

- `cmd/main/tui/tui.mbt`

Startup call chain:

```text
moonclaw tui [flags]
  -> cmd/main/tui/tui.mbt::tui_interactive(args)
    -> parse flags
    -> @model.load(name?=model)
    -> Moonclaw::new(...) or Moonclaw::resume_(...)
    -> @tui.TUI::new()
    -> initialize TUI state from live agent
    -> register keyboard callbacks
    -> register agent event listener
    -> spawn TUI loop + agent loop
```

## Supported Flags

Current flags:

- `--prompt` / `-p`
- `--model` / `-m`
- `--web-search`
- `--log-file`
- `--resume` / `-r`

## Runtime Components

Main implementation files:

- `internal/tui/tui.mbt`
- `internal/tui/chat_log.mbt`
- `internal/tui/editor.mbt`
- `internal/tui/tui_state.mbt`
- related component files under `internal/tui/`

`TUI` owns:

- terminal
- chat log
- editor
- header/footer texts
- status loader / status text
- mutable `TuiState`
- lifecycle callbacks

## TUI State Initialization

At startup, the CLI layer now seeds the UI from the actual agent:

```text
tui.state().set_model(moonclaw.agent.model.name)
tui.state().set_agent_id(moonclaw.agent.id().to_string())
tui.state().set_session_key(moonclaw.agent.id().to_string())
```

This matters because earlier drafts assumed those fields were decorative. In the current implementation they are live runtime identifiers shown in the header/footer.

## Input Flow

### Normal text submission

```text
user types text
  -> Editor submit
  -> TUI on_submit callback
  -> chat_log.add_user(...)
  -> moonclaw.agent.queue_message(user_message)
  -> request_render()
```

### Slash commands

Slash-prefixed input is parsed by `@tui.parse_command(...)` and handled in `handle_command(...)`.

Current built-in commands:

- `/clear`
- `/help`
- `/model`
- `/exit`

These are implemented in the CLI wrapper, not in the low-level `internal/tui` package.

## Keyboard Handling

Current wiring in `cmd/main/tui/tui.mbt` and `internal/tui/tui.mbt`:

- `Ctrl-C`: request clean exit
- `Ctrl-D`: request exit
- `Ctrl-O`: toggle tool expansion
- `Up` / `Down`: chat scroll
- `PageUp` / `PageDown`: larger chat scroll
- editor-specific movement/editing keys are delegated to `Editor`

Important current behavior:

- `Ctrl-C` no longer does nothing; it sets stopping state and exits
- `Ctrl-O` toggles `TuiState` and updates `ChatLog`

## Render Flow

`internal/tui/tui.mbt::render()` is the central render pass.

Current order:

```text
render()
  -> update_header()
  -> update_footer()
  -> update_status()
  -> clear_screen()
  -> render header
  -> render chat log
  -> render loader or status text
  -> render footer
  -> render editor
  -> flush terminal
```

The important implementation fix here is that header/footer/status are refreshed during every render, so state changes are not left stale on screen.

## Agent Event Flow Into the TUI

`cmd/main/tui/tui.mbt` attaches a listener to `moonclaw.agent`.

Current mapping:

| Agent event | TUI effect |
|---|---|
| `MessageQueued` | status -> `message queued` |
| `PreConversation` | status -> `starting conversation` |
| `TokenCounted` | show token count in status |
| `ContextPruned` | show pruning summary |
| `AssistantMessage` | update streaming assistant text in chat log |
| `PreToolCall` | create tool execution entry |
| `PostToolCall` | update tool result entry |
| `PostConversation` | mark current assistant block complete |
| `Failed` | status -> failure text |
| `Cancelled` | status -> cancelled |

Message flow:

```text
agent emits event
  -> listener in cmd/main/tui/tui.mbt
    -> update TuiState and/or ChatLog
    -> request_render()
```

## Agent Loop

The TUI runs two background tasks:

### UI loop

```text
group.spawn_bg
  -> tui.start()
  -> tui.run_event_loop()
```

### Agent loop

```text
group.spawn_bg
  -> set connection status = connected
  -> while not exiting:
       moonclaw.agent.start()
       sleep(50ms)
```

This means the TUI is local-first: it is not talking to the gateway. It drives a local `Moonclaw` instance directly.

## Message and Tool Display Semantics

Current behavior in the TUI stack:

- user messages are appended immediately on submit
- assistant content is updated incrementally during streaming
- tool calls open a placeholder entry on `PreToolCall`
- tool results replace that placeholder on `PostToolCall`
- the current assistant block is finalized on `PostConversation`

Tool expansion state is global and controlled by `Ctrl-O`.

## Known Boundaries

Current TUI is intentionally narrower than the large earlier design:

- no gateway-backed remote session mode
- no command palette
- no autocomplete
- no multi-pane orchestration view
- no mailbox/coordination/pipeline inspector

What it does well today:

- local conversation loop
- live status updates
- streamed assistant rendering
- tool execution visibility
- stable exit behavior
