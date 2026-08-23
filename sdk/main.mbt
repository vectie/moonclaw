///|
async fn @stdio.Output::writeln(self : @stdio.Output, str : String) -> Unit {
  self.write(str + "\n")
}

///|
async fn execute(prompt~ : String, model? : String) -> Unit {
  try {
    guard @model.load(name?=model) is Some(model) else {
      let error : Json = {
        "error": {
          "code": -1,
          "message": "No model available; please configure a model first.",
        },
      }
      println(error.stringify())
      return
    }
    let moonclaw = @moonclaw.Moonclaw::new(model~, user_message=prompt)
    moonclaw.agent.add_listener(event => {
      match event.desc {
        ToolAdded(desc) => {
          let response : Json = {
            "method": "moonclaw.agent.tool_added",
            "params": { "tool": desc },
          }
          @stdio.stdout.writeln(response.stringify())
        }
        UserMessage(content) => {
          let response : Json = {
            "method": "moonclaw.agent.message",
            "params": { "message": { "role": "user", "content": content } },
          }
          @stdio.stdout.writeln(response.stringify())
        }
        PreConversation => {
          let response : Json = {
            "method": "moonclaw.agent.conversation_start",
            "params": {},
          }
          @stdio.stdout.writeln(response.stringify())
        }
        PostConversation => {
          let response : Json = {
            "method": "moonclaw.agent.conversation_end",
            "params": {},
          }
          @stdio.stdout.writeln(response.stringify())
        }
        AssistantMessage(usage~, tool_calls~, content) => {
          let usage = usage.map(fn(u) { u.to_openai() })
          let message = @openai.assistant_message(
            content~,
            tool_calls=tool_calls.map(fn(tc) { tc.to_openai() }),
          )
          let response : Json = {
            "method": "moonclaw.agent.request_completed",
            "params": { "usage": usage, "message": message },
          }
          @stdio.stdout.writeln(response.stringify())
        }
        PostToolCall(tool_call, result~, rendered~) => {
          let tool_call = tool_call.to_openai()
          let response : Json = {
            "method": "moonclaw.agent.post_tool_call",
            "params": {
              "tool_call": tool_call,
              "json": result,
              "text": rendered,
            },
          }
          @stdio.stdout.writeln(response.stringify())
        }
        _ => ()
      }
    })
    moonclaw.start()
  } catch {
    @io.ReaderClosed => ()
    error => {
      let error : Json = {
        "error": { "code": -1, "message": "\{Repr(error)}" },
      }
      println(error.stringify())
    }
  }
}

///|
async fn main {
  @backtrace.initialize()
  let args = @os.args()
  let mut prompt = None
  let mut model = None
  for args = args[1:] {
    match args {
      ["exec" | "execute" | "-p" | "--prompt", p, .. args] =>
        if p.has_prefix("-") {
          let error : Json = {
            "error": {
              "code": -1,
              "message": "\{Repr(Failure::Failure("Expect <prompt> after -p/--prompt"))}",
            },
          }
          println(error.stringify())
        } else {
          prompt = Some(p)
          continue args
        }
      ["-m" | "--model", m, .. args] =>
        if m.has_prefix("-") {
          let error : Json = {
            "error": {
              "code": -1,
              "message": "\{Repr(Failure::Failure("Expect <model> after -m/--model"))}",
            },
          }
          println(error.stringify())
        } else {
          model = Some(m)
          continue args
        }
      [unknown, ..] => {
        let error : Json = {
          "error": {
            "code": -1,
            "message": "\{Repr(Failure::Failure("Unknown argument: \{unknown}"))}",
          },
        }
        println(error.stringify())
      }
      [] => break
    }
  }
  guard prompt is Some(prompt) else {
    let failure = Failure::Failure(
      "Missing required argument: -p/--prompt <prompt>",
    )
    let error : Json = {
      "error": { "code": -1, "message": "\{Repr(failure)}" },
    }
    println(error.stringify())
    return
  }
  execute(prompt~, model?)
}
