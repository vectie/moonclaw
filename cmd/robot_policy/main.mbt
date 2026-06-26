///|
fn usage() -> Unit {
  println("MoonClaw Robot Policy")
  println("")
  println("Usage:")
  println("  moon run cmd/robot_policy -- <moonrobo-context.json>")
  println("")
  println("Reads a Moonrobo /api/moonclaw/context JSON payload and prints the")
  println("MoonClaw-owned route decision as JSON.")
}

///|
async fn main {
  let args = @os.args()
  match args[:] {
    [_bin, "--help"] | [_bin, "-h"] => usage()
    [_bin, path] => {
      let text = @fsx.read_file(path) catch {
        error => {
          println(
            {
              "status": Json::string("error"),
              "message": Json::string(
                "failed to read Moonrobo context file: \{error}",
              ),
            }
            .to_json()
            .stringify(),
          )
          return
        }
      }
      match @policy.select_route_from_context_text(text) {
        Ok(decision) => println(decision.to_json().stringify(indent=2))
        Err(message) =>
          println(
            {
              "status": Json::string("error"),
              "message": Json::string(message),
            }
            .to_json()
            .stringify(),
          )
      }
    }
    _ => usage()
  }
}
