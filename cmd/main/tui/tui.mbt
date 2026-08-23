///|
priv struct TuiState {
  mut should_exit : Bool
  mut pending_assistant_text : String?
  mut stream_dirty : Bool
}

///|
const StreamFlushIntervalMs : Int = 120

///|
async fn println(msg : String) -> Unit {
  @stdio.stdout.write("\{msg}\n")
}

///|
pub async fn tui_interactive(args : ArrayView[String]) -> Unit {
  let mut prompt : String? = None
  let mut model : String? = None
  let mut web_search : Bool = false
  let mut log_file : String? = None
  let mut resume_id : @uuid.Uuid? = None
  let mut agent_kind = "code"
  for args = args {
    match args {
      ["--prompt" | "-p", value, .. rest] => {
        prompt = Some(value)
        continue rest
      }
      ["--model" | "-m", value, .. rest] => {
        model = Some(value)
        continue rest
      }
      ["--web-search", .. rest] => {
        web_search = true
        continue rest
      }
      ["--log-file", value, .. rest] => {
        log_file = Some(value)
        continue rest
      }
      ["--agent", value, .. rest] => {
        match value {
          "code" | "coder" => agent_kind = "code"
          "general" | "chat" => agent_kind = "general"
          _ =>
            raise @argument.InvalidArgument(
              "--agent must be either 'code' or 'general', got '\{value}'",
            )
        }
        continue rest
      }
      ["--resume" | "-r", value, .. rest] => {
        let value = @uuid.parse(value) catch {
          _ =>
            raise @argument.InvalidArgument(
              "Invalid resume ID: '\{value}' is not a valid UUID.",
            )
        }
        resume_id = Some(value)
        continue rest
      }
      [unknown, ..] => raise @argument.InvalidArgument(unknown)
      [] => break
    }
  }
  @moongate_startup.print_status()
  let logger = match log_file {
    Some(log_file) =>
      Some(@pino.logger("moonclaw", @pino.Transport::file(log_file)))
    None => None
  }
  guard @model.load(name?=model) is Some(model) else {
    println("No model available; please configure a model first.")
    return
  }
  if agent_kind == "general" && resume_id is Some(_) {
    raise @argument.InvalidArgument(
      "--resume is currently supported only with --agent code",
    )
  }

  @async.with_task_group(group => {
    let agent = if agent_kind == "code" {
      let moonclaw = if resume_id is Some(id) {
        @moonclaw.Moonclaw::resume_(model~, id, web_search~, logger?)
      } else {
        @moonclaw.Moonclaw::new(model~, web_search~, logger?)
      }
      moonclaw.agent
    } else {
      @agent.new(
        name="General Chat",
        model,
        logger?,
        cwd=@os.cwd(),
        system_message="You are a concise general-purpose assistant.",
        web_search~,
      )
    }

    let tui = @itui.TUI::new() catch {
      error => {
        println("Failed to initialize TUI: \{error}")
        return
      }
    }

    let state = TuiState::{
      should_exit: false,
      pending_assistant_text: None,
      stream_dirty: false,
    }
    tui.state().set_model(agent.model.name)
    tui.state().set_agent_kind(agent_kind)
    tui.state().set_agent_id(agent.id().to_string())
    tui.state().set_session_key(agent.id().to_string())

    tui.set_on_submit(fn(text : String) {
      let (width, height) = tui.terminal().size()
      let chat_height = height - 4 // Account for header, footer, and editor
      tui.chat_log().add_user(text, width, chat_height)
      tui.state().set_busy(true)
      tui.state().set_activity_status("message queued")
      agent.queue_message(@ai.user_message(content=text)) |> ignore()
      tui.request_render()
    })

    tui.set_on_command(fn(text : String) {
      let (cmd, args) = @itui.parse_command(text)
      handle_command(tui, agent, agent_kind, cmd, args, state)
      tui.request_render()
    })

    tui.set_on_ctrl_c(fn() {
      state.should_exit = true
      tui.request_stop()
      tui.state().set_activity_status("stopping")
      tui.request_render()
    })

    tui.set_on_ctrl_d(fn() {
      state.should_exit = true
      tui.request_stop()
      tui.state().set_activity_status("stopping")
      tui.request_render()
    })

    tui
    .editor()
    .set_on_ctrl_c(fn() {
      state.should_exit = true
      tui.request_stop()
      tui.state().set_activity_status("stopping")
      tui.request_render()
    })

    tui
    .editor()
    .set_on_ctrl_d(fn() {
      state.should_exit = true
      tui.request_stop()
      tui.state().set_activity_status("stopping")
      tui.request_render()
    })

    tui.set_on_ctrl_o(fn() {
      let expanded = tui.state().toggle_tools_expanded()
      tui.chat_log().set_tools_expanded(expanded)
      tui.request_render()
    })

    agent.add_listener(event => {
      match event.desc {
        MessageQueued(_) => {
          tui.state().set_busy(true)
          tui.state().set_activity_status("message queued")
          tui.request_render()
        }
        PreConversation => {
          tui.state().set_busy(true)
          tui.state().set_activity_status("starting conversation")
          tui.request_render()
        }
        TokenCounted(count) => {
          tui.state().set_busy(true)
          tui.state().set_activity_status("tokens: \{count}")
          tui.request_render()
        }
        ContextPruned(origin_token_count~, pruned_token_count~) => {
          tui.state().set_busy(true)
          tui
          .state()
          .set_activity_status(
            "context pruned: \{origin_token_count} -> \{pruned_token_count}",
          )
          tui.request_render()
        }
        AssistantMessage(content, ..) => {
          tui.state().set_busy(true)
          tui.state().set_activity_status("receiving response")
          if !content.is_blank() {
            state.pending_assistant_text = Some(content)
            state.stream_dirty = true
          }
        }
        PreToolCall(tool_call) => {
          flush_pending_stream(tui, state)
          tui.state().set_busy(true)
          tui.state().set_activity_status("calling tool: \{tool_call.name}")
          ignore(
            tui
            .chat_log()
            .start_tool(
              tool_call.id,
              tool_call.name,
              tool_call.arguments.unwrap_or(""),
            ),
          )
          tui.scroll_chat_to_bottom()
          tui.request_render()
        }
        PostToolCall(tool_call, result~, rendered~) => {
          flush_pending_stream(tui, state)
          tui.state().set_busy(true)
          tui.state().set_activity_status("tool done: \{tool_call.name}")
          let is_error = match result {
            Err(_) => true
            Ok(_) => false
          }
          tui.chat_log().update_tool_result(tool_call.id, rendered, is_error~)
          tui.scroll_chat_to_bottom()
          tui.request_render()
        }
        PostConversation => {
          flush_pending_stream(tui, state)
          tui.state().set_busy(false)
          tui.state().set_activity_status("idle")
          // Mark the streaming assistant as done so the next one starts fresh
          // Don't pass empty text, just finalize with current content
          tui.chat_log().finalize_current_assistant()
          tui.scroll_chat_to_bottom()
          tui.request_render()
        }
        Failed(err) => {
          flush_pending_stream(tui, state)
          tui.state().set_busy(false)
          tui.state().set_activity_status("failed: \{Repr(err)}")
          tui.request_render()
        }
        Cancelled => {
          flush_pending_stream(tui, state)
          tui.state().set_busy(false)
          tui.state().set_activity_status("cancelled")
          tui.request_render()
        }
        _ => ()
      }
    })

    group.spawn_bg(() => {
      tui.start()
      tui.run_event_loop()
    })

    group.spawn_bg(() => {
      tui.state().set_connection_status("connected")
      tui.request_render()
      while !state.should_exit {
        agent.start() catch {
          error => println("Error: \{error}")
        }
        @async.sleep(50)
      }
    })

    group.spawn_bg(() => {
      while !state.should_exit {
        if state.stream_dirty {
          flush_pending_stream(tui, state)
        }
        @async.sleep(StreamFlushIntervalMs)
      }
    })

    if prompt is Some(prompt) {
      let (width, height) = tui.terminal().size()
      let chat_height = height - 4
      tui.chat_log().add_user(prompt, width, chat_height)
      tui.state().set_busy(true)
      tui.state().set_activity_status("message queued")
      agent.queue_message(@ai.user_message(content=prompt)) |> ignore()
    }

    while tui.is_running() && !state.should_exit {
      @async.sleep(100)
    }

    if state.should_exit {
      tui.stop()
    }

    agent.close()
  })
}

///|
fn flush_pending_stream(tui : @itui.TUI, state : TuiState) -> Unit {
  if state.pending_assistant_text is Some(content) {
    tui.chat_log().update_assistant(content)
    tui.scroll_chat_to_bottom()
    tui.request_render()
  }
  state.pending_assistant_text = None
  state.stream_dirty = false
}

///|
fn handle_command(
  tui : @itui.TUI,
  agent : @agent.Agent,
  agent_kind : String,
  cmd : String,
  _args : String,
  state : TuiState,
) -> Unit {
  let (width, height) = tui.terminal().size()
  let chat_height = height - 4
  match cmd {
    "clear" => tui.chat_log().clear_all()
    "help" => {
      let help_text = "Available commands:\n/clear - Clear chat history\n/help - Show this help message\n/model - Show current model and agent mode\n/exit - Exit the application\n\nStart modes: moonclaw tui --agent code | --agent general"
      tui.chat_log().add_system(help_text, width, chat_height)
    }
    "model" => {
      let model_info = "Current model: \{agent.model.name}\nAgent mode: \{agent_kind}"
      tui.chat_log().add_system(model_info, width, chat_height)
    }
    "exit" => {
      state.should_exit = true
      tui.request_stop()
    }
    _ => {
      let error_msg = "Unknown command: /\{cmd}"
      tui.chat_log().add_system(error_msg, width, chat_height)
    }
  }
  tui.request_render()
}
