///|
async fn println(msg : String) -> Unit {
  @stdio.stdout.write("\{msg}\n")
}

///|
pub async fn interactive(args : ArrayView[String]) -> Unit {
  let mut prompt : String? = None
  let mut model : String? = None
  let mut web_search : Bool = false
  let mut log_file : String? = None
  let mut resume_id : @uuid.Uuid? = None
  let mut use_tui : Bool = false
  loop args {
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
    ["--tui", .. rest] => {
      use_tui = true
      continue rest
    }
    [unknown, ..] => raise @argument.InvalidArgument(unknown)
    [] => break
  }

  if use_tui {
    @tui.tui_interactive(args)
    return
  }

  let logger = match log_file {
    Some(log_file) =>
      Some(@pino.logger("moonclaw", @pino.Transport::file(log_file)))
    None => None
  }
  guard @model.load(name?=model) is Some(model) else {
    println("No model available; please configure a model first.")
    return
  }
  @async.with_task_group(group => {
    let moonclaw = if resume_id is Some(id) {
      @moonclaw.Moonclaw::resume_(model~, id, web_search~, logger?)
    } else {
      @moonclaw.Moonclaw::new(model~, web_search~, logger?)
    }
    moonclaw.agent.add_listener(event => {
      match event.desc {
        AssistantMessage(content, ..) =>
          if !content.is_blank() {
            println(content)
          }
        PreToolCall(tool_call) =>
          match tool_call.arguments {
            None => println("% \{tool_call.name}")
            Some(arguments) =>
              try {
                let arguments = @json.parse(arguments)
                println("% \{tool_call.name} \{arguments.stringify(indent=2)}")
              } catch {
                _ => println("% \{tool_call.name}\n  \{arguments}")
              }
          }
        PostToolCall(_, rendered~, ..) => {
          let lines = rendered.split("\n").collect()
          for i = 0; i < lines.length(); i = i + 1 {
            let text = lines[i]
            println("> \{text}")
          }
        }
        _ => ()
      }
    })
    async fn clear_inputs_and_prompt(
      moonclaw : @moonclaw.Moonclaw,
      rl : @readline.Interface,
    ) -> Unit {
      let qms = moonclaw.agent.clear_inputs()
      for qm in qms {
        rl.set_prompt("$ ")
        rl.set_line(@encoding/utf8.encode(qm.message.content()))
        rl.prompt()
        break
      }
    }

    let rl = @readline.interface(input=@stdio.stdin, output=@stdio.stdout)
    let mut task : @async.Task[Unit]? = None
    group.spawn_bg(() => {
      for {
        rl.start() catch {
          @readline.CtrlC =>
            if task is Some(round) {
              round.cancel()
              clear_inputs_and_prompt(moonclaw, rl)
            } else {
              // Clear the current input line
              println("")
              rl.set_line("")
              // Re-prompt the user
              rl.set_prompt("$ ")
              rl.prompt()
              continue
            }
          error => raise error
        }
      }
    })
    if prompt is Some(prompt) {
      println("$ \{prompt}")
      let round = group.spawn(
        () => {
          moonclaw.start(prompt~) catch {
            error => {
              println("! \{error}")
              clear_inputs_and_prompt(moonclaw, rl)
            }
          }
        },
        allow_failure=true,
      )
      task = Some(round)
      defer {
        task = None
      }
      round.wait() catch {
        _ => ()
      }
    }
    while true {
      rl.set_prompt("$ ")
      rl.prompt()
      let prompt = rl.read_line()
      let round = group.spawn(
        () => {
          moonclaw.start(prompt~) catch {
            error => {
              println("! \{error}")
              clear_inputs_and_prompt(moonclaw, rl)
            }
          }
        },
        allow_failure=true,
      )
      task = Some(round)
      defer {
        task = None
      }
      round.wait() catch {
        _ => ()
      }
    }
  })
}
