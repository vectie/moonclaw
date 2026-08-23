///|
fn harness_replay_cli_usage() -> String {
  "Usage: moon run --target native cmd/harness_replay -- <fixture.json>\n"
}

///|
fn harness_replay_cli_error(code : String) -> Json {
  {
    "contract": "moonclaw.harness-replay-cli-error.v1",
    "ok": false,
    "error": code,
  }
}

///|
fn harness_replay_cli_passed(report : Json) -> Bool {
  match report {
    Object(fields) =>
      match fields.get("overall_passed") {
        Some(True) => true
        _ => false
      }
    _ => false
  }
}

///|
async fn main {
  let args = @os.args()
  let arguments = args[1:]
  if arguments is ["--help" | "-h"] {
    @stdio.stdout.write(harness_replay_cli_usage())
    return
  }
  guard arguments is [fixture_path] else {
    @stdio.stdout.write(
      harness_replay_cli_error("expected-one-fixture-path").stringify() + "\n",
    )
    @os.exit(2)
  }
  let fixture = @json.parse(@fsx.read_file(fixture_path)) catch {
    _ => {
      @stdio.stdout.write(
        harness_replay_cli_error("fixture-read-or-parse-failed").stringify() +
        "\n",
      )
      @os.exit(2)
    }
  }
  let report = @replay.evaluate_harness_replay(fixture) catch {
    InvalidFixture(code) => {
      @stdio.stdout.write(harness_replay_cli_error(code).stringify() + "\n")
      @os.exit(2)
    }
  }
  @stdio.stdout.write(report.stringify(indent=2) + "\n")
  if !harness_replay_cli_passed(report) {
    @os.exit(1)
  }
}
