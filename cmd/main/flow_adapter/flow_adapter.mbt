///|
fn option(args : Array[String], flag : String) -> String? {
  for index in 0..<(args.length() - 1) {
    if args[index] == flag {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn required_option(args : Array[String], flag : String) -> String raise {
  match option(args, flag) {
    Some(value) if !value.trim().is_empty() => value
    _ => fail("MoonClaw flow adapter requires \{flag}")
  }
}

///|
fn repeated_option(args : Array[String], flag : String) -> Array[String] {
  let values : Array[String] = []
  for index in 0..<(args.length() - 1) {
    if args[index] == flag {
      values.push(args[index + 1])
    }
  }
  values
}

///|
fn safe_ref(reference : String) -> Bool {
  let value = reference.trim().replace(old="\\", new="/")
  !value.is_empty() &&
  !value.has_prefix("/") &&
  !value.split("/").any(part => part.is_empty() || part == "..")
}

///|
fn require_ref(reference : String, label : String) -> String raise {
  if !safe_ref(reference) {
    fail("MoonClaw flow adapter \{label} must be workspace-relative")
  }
  reference
}

///|
async fn read_json(path : String) -> Json {
  @json.parse(@fsx.read_file(path))
}

///|
async fn write_json(path : String, value : Json) -> Unit {
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fsx.write_to_file(path, value.stringify(indent=2) + "\n", create=0o644)
}

///|
fn string_field(fields : Map[String, Json], key : String) -> String raise {
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() => value
    _ => fail("MoonClaw flow request requires \{key}")
  }
}

///|
fn object(value : Json, label : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => fail("MoonClaw \{label} must be a JSON object")
  }
}

///|
fn hex_digit(value : Int) -> Char {
  if value < 10 {
    ('0'.to_int() + value).unsafe_to_char()
  } else {
    ('a'.to_int() + value - 10).unsafe_to_char()
  }
}

///|
fn sha256_hex(bytes : Bytes) -> String {
  let digest = @crypto.sha256(bytes)
  let builder = StringBuilder::new()
  for byte in digest {
    let value = byte.to_int()
    builder.write_char(hex_digit(value / 16))
    builder.write_char(hex_digit(value % 16))
  }
  builder.to_string()
}

///|
async fn artifact_digest(
  workspace : String,
  artifacts : Array[String],
) -> String {
  let identities : Array[String] = []
  for artifact in artifacts {
    let data = @fs.read_file(
      workspace + "/" + require_ref(artifact, "artifact"),
    )
    identities.push("\{artifact}|sha256:\{sha256_hex(data.binary())}")
  }
  "sha256:" + sha256_hex(@utf8.encode(identities.join("\n")))
}

///|
async fn execute_agent(
  workspace : String,
  model_name : String,
  prompt : String,
  log_path : String,
  web_search : Bool,
) -> Unit {
  let model = @model.load(name=model_name)
  guard model is Some(model) else {
    fail("MoonClaw flow adapter model is unavailable: \{model_name}")
  }
  let logger = @pino.logger(
    "moonclaw_flow_adapter",
    try! @pino.Transport::parse("file:\{log_path}"),
  )
  let worker = @moonclaw.Moonclaw::new(
    name="moonflow-worker",
    logger~,
    model~,
    cwd=workspace,
    user_message=prompt,
    web_search~,
  )
  defer worker.close()
  worker.start()
}

///|
fn execution_prompt(
  request : Json,
  artifacts : Array[String],
  trial : Int,
) -> String {
  "You are a bounded MoonFlow product adapter executing one declared digital work item.\n" +
  "The immutable request follows:\n```json\n" +
  request.stringify(indent=2) +
  "\n```\n" +
  "Write exactly these declared output artifacts, relative to the workspace: " +
  artifacts.join(", ") +
  ".\nRead every declared input artifact before acting. Preserve sources, uncertainty, contradictions, negative cases, and trial evidence appropriate to the product and operation. Do not weaken or rewrite acceptance criteria. Do not claim physical construction, deployment, or readiness. Do not write the MoonFlow result receipt; the adapter wrapper owns it. This is bounded trial " +
  "\{trial}. If prior partial artifacts exist, diagnose and improve them rather than hiding the failure."
}

///|
async fn execute(args : Array[String]) -> Unit {
  let workspace = required_option(args, "--workspace")
  let request_ref = require_ref(required_option(args, "--request"), "request")
  let result_ref = require_ref(required_option(args, "--result"), "result")
  let model_name = required_option(args, "--model")
  let artifacts = repeated_option(args, "--artifact")
  if artifacts.is_empty() {
    fail("MoonClaw flow adapter requires at least one --artifact")
  }
  for artifact in artifacts {
    ignore(require_ref(artifact, "output artifact"))
  }
  let max_trials = match option(args, "--max-trials") {
    Some(value) => @string.parse_int(value)
    None => 3
  }
  if max_trials < 1 || max_trials > 10 {
    fail("MoonClaw flow adapter max trials must be between 1 and 10")
  }
  let request = read_json(workspace + "/" + request_ref)
  let fields = object(request, "flow request")
  let attempt_id = string_field(fields, "attempt_id")
  let run_root = workspace + "/.moonsuite/products/moonclaw/flow/" + attempt_id
  @fsx.make_directory(run_root, recursive=true, exists_ok=true)
  let mut completed = false
  let mut trials = 0
  while trials < max_trials && !completed {
    trials += 1
    execute_agent(
      workspace,
      model_name,
      execution_prompt(request, artifacts, trials),
      run_root + "/trial-\{trials}.jsonl",
      true,
    ) catch {
      _ => ()
    }
    completed = true
    for artifact in artifacts {
      if !@fsx.exists(workspace + "/" + artifact) {
        completed = false
      }
    }
  }
  let output_digest = if completed {
    artifact_digest(workspace, artifacts)
  } else {
    ""
  }
  write_json(workspace + "/" + result_ref, {
    "result_id": "result-" +
    attempt_id +
    (if completed { "-succeeded" } else { "-failed" }),
    "request_id": string_field(fields, "request_id"),
    "attempt_id": attempt_id,
    "idempotency_key": string_field(fields, "idempotency_key"),
    "product_id": string_field(fields, "product_id"),
    "external_job_id": "moonclaw-" + attempt_id,
    "status": if completed {
      "succeeded"
    } else {
      "failed"
    },
    "output_digest": output_digest,
    "output_artifacts": if completed {
      artifacts.to_json()
    } else {
      Json::array([])
    },
    "error_kind": if completed {
      ""
    } else {
      "declared-artifacts-missing"
    },
    "compensable": true,
    "recorded_at": string_field(fields, "created_at"),
    "trial_count": trials,
  })
  if !completed {
    fail("MoonClaw flow adapter exhausted trials without declared artifacts")
  }
}

///|
fn review_prompt(packet : Json) -> String {
  "You are an independent MoonFlow acceptance reviewer. You did not execute this work.\n" +
  "Review the immutable request below and inspect the exact evidence files it names. Decide every criterion in the original order. A satisfied criterion requires specific evidence_refs; never accept an executor summary alone. Reject missing negative cases, digest or identity concerns, unsupported claims, and any physical-readiness overclaim. Preserve limitations and dissent. You may not grant authority or change criteria. Write exactly one moonflow.acceptance-review.v1 JSON receipt at receipt_artifact using the supplied identities, reviewer_id, review_authority_id, and recorded_at.\n```json\n" +
  packet.stringify(indent=2) +
  "\n```"
}

///|
async fn review(args : Array[String]) -> Unit {
  let workspace = required_option(args, "--workspace")
  let packet_ref = require_ref(
    required_option(args, "--review-packet"),
    "review packet",
  )
  let model_name = required_option(args, "--model")
  let packet = read_json(workspace + "/" + packet_ref)
  let fields = object(packet, "review packet")
  let receipt_ref = require_ref(
    string_field(fields, "receipt_artifact"),
    "receipt artifact",
  )
  let attempt_id = string_field(fields, "attempt_id")
  let log_root = workspace +
    "/.moonsuite/products/moonclaw/reviews/" +
    attempt_id
  @fsx.make_directory(log_root, recursive=true, exists_ok=true)
  execute_agent(
    workspace,
    model_name,
    review_prompt(packet),
    log_root + "/review.jsonl",
    false,
  )
  if !@fsx.exists(workspace + "/" + receipt_ref) {
    fail("MoonClaw independent reviewer omitted its declared receipt")
  }
}

///|
pub async fn run(args : ArrayView[String]) -> Unit {
  let owned = args.to_owned()
  match owned {
    ["execute", .. rest] => execute(rest.to_owned())
    ["review", .. rest] => review(rest.to_owned())
    _ =>
      println(
        "moonclaw flow-adapter usage:\n  moonclaw flow-adapter execute --workspace <root> --request <ref> --result <ref> --model <id> --artifact <ref>... [--max-trials <n>]\n  moonclaw flow-adapter review --workspace <root> --review-packet <ref> --model <id>",
      )
  }
}
