///|
const MoonDeskSandboxRequestBytes : Int = 8_192

///|
const MoonDeskSandboxOutputBytes : Int = 160_000

///|
const MoonDeskSandboxTimeoutMs : Int = 60_000

///|
priv struct MoonDeskMoonDiagnosticsRequest {
  protocol_version : Int
  instance_id : String
  request_id : String
  workspace_id : String
  module_directory : String
  target : String
} derive(@json.FromJson)

///|
fn moondesk_sandbox_safe_request_id(value : String) -> Bool {
  value.length() >= 16 &&
  value.length() <= 128 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_'
  })
}

///|
fn moondesk_sandbox_safe_relative_directory(value : String) -> Bool {
  value.length() <= 4_096 &&
  !value.has_prefix("/") &&
  !value.has_suffix("/") &&
  !value.contains("//") &&
  !value.contains("\u{0}") &&
  !value.split("/").any(component => component == "." || component == "..")
}

///|
fn moondesk_sandbox_constant_time_equal(left : String, right : String) -> Bool {
  let left_length = left.length()
  let right_length = right.length()
  let mut mismatch = left_length ^ right_length
  // Iterate for the configured credential length even when the attacker sends
  // a shorter or longer value. Credential length is fixed and non-secret.
  for index in 0..<right_length {
    let left_byte = if index < left_length { left[index].to_int() } else { 0 }
    mismatch = mismatch | (left_byte ^ right[index].to_int())
  }
  mismatch == 0
}

///|
async fn moondesk_sandbox_directory(
  config : @moondesk_sandbox_config.Config,
  relative : String,
) -> String {
  guard moondesk_sandbox_safe_relative_directory(relative) else {
    fail("invalid module directory")
  }
  let candidate = if relative == "" {
    config.workspace_root
  } else {
    @pathx.join(config.workspace_root, relative)
  }
  guard @fsx.resolve(config.workspace_root) == config.workspace_root &&
    @fsx.resolve(candidate) == candidate &&
    (
      candidate == config.workspace_root ||
      candidate.has_prefix(config.workspace_root + "/")
    ) &&
    @fsx.exists(candidate) else {
    fail("module directory is outside the registered workspace")
  }
  candidate
}

///|
fn moondesk_sandbox_parse_request(
  json : Json,
) -> MoonDeskMoonDiagnosticsRequest raise {
  let request : MoonDeskMoonDiagnosticsRequest = @json.from_json(json) catch {
    _ => fail("invalid typed sandbox request")
  }
  guard request.protocol_version == 1 &&
    moondesk_sandbox_safe_request_id(request.request_id) &&
    request.target == "" &&
    moondesk_sandbox_safe_relative_directory(request.module_directory) else {
    fail("invalid typed sandbox request")
  }
  request
}

///|
async fn moondesk_sandbox_read_request(r : @httpx.RequestReader) -> Json {
  moondesk_sandbox_read_request_bounded(r, MoonDeskSandboxRequestBytes)
}

///|
async fn moondesk_sandbox_read_request_bounded(
  r : @httpx.RequestReader,
  limit : Int,
) -> Json {
  let output = @buffer.Buffer(size_hint=1_024)
  for ;; {
    guard r.body.read_some(max_len=(limit - output.length() + 1).min(2_048))
      is Some(chunk) else {
      break
    }
    guard output.length() + chunk.length() <= limit else {
      raise json_error(413, "PayloadTooLarge", {
        "error": {
          "code": "request_too_large",
          "message": "request body exceeds the limit",
        },
      })
    }
    output.write_bytes(chunk)
  }
  @json.parse(@encoding/utf8.decode(output.to_bytes())) catch {
    _ =>
      raise json_error(400, "BadRequest", {
        "error": { "code": "invalid_json", "message": "invalid JSON body" },
      })
  }
}

///|
fn moondesk_sandbox_bounded_output(text : String) -> (String, Bool) {
  let encoded = @encoding/utf8.encode(text)
  if encoded.length() <= MoonDeskSandboxOutputBytes {
    (text, false)
  } else {
    (@encoding/utf8.decode_lossy(encoded[:MoonDeskSandboxOutputBytes]), true)
  }
}

///|
async fn execute_moondesk_moon_diagnostics(
  executor_config : @execution_sandbox.SandboxExecutorConfig,
  route_config : @moondesk_sandbox_config.Config,
  request : MoonDeskMoonDiagnosticsRequest,
) -> Json {
  guard request.instance_id == route_config.instance_id &&
    request.workspace_id == route_config.workspace_id &&
    executor_config.workspace_id == route_config.workspace_id else {
    fail("sandbox request binding does not match the configured instance")
  }
  let working_directory = moondesk_sandbox_directory(
    route_config,
    request.module_directory,
  )
  let execution = @execution_sandbox.run_moon_diagnostics(
    executor_config,
    route_config.workspace_root,
    working_directory,
    request.target,
    MoonDeskSandboxTimeoutMs,
  )
  let receipt = execution.receipt
  guard receipt.status is Exited &&
    receipt.exit_code is Some(exit_code) &&
    receipt.enforcement is Enforced &&
    receipt.cleanup_verified else {
    fail("MoonFort did not return a verified terminal diagnostics receipt")
  }
  let (output, transport_truncated) = moondesk_sandbox_bounded_output(
    receipt.output,
  )
  {
    "protocol_version": 1,
    "instance_id": route_config.instance_id,
    "request_id": request.request_id,
    "workspace_id": route_config.workspace_id,
    "operation": "moon_diagnostics",
    "exit_code": exit_code,
    "output": output,
    "output_truncated": receipt.output_truncated || transport_truncated,
    "receipt": {
      "run_id": receipt.run_id,
      "approval_id": receipt.approval_id,
      "approval_digest": receipt.approval_digest,
      "command_digest": receipt.command_digest,
      "profile_digest": receipt.profile_digest,
      "backend": receipt.backend,
      "enforcement": receipt.enforcement,
      "cleanup_verified": receipt.cleanup_verified,
    },
  }
}

///|
async fn Daemon::moondesk_moon_diagnostics(
  self : Daemon,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  ignore(self)
  let route_config = @moondesk_sandbox_config.load() catch {
    _ =>
      raise json_error(503, "ServiceUnavailable", {
        "error": {
          "code": "sandbox_unavailable",
          "message": "execution sandbox route is unavailable",
        },
      })
  }
  guard route_config is Some(route_config) else {
    raise json_error(503, "ServiceUnavailable", {
      "error": {
        "code": "sandbox_unavailable",
        "message": "execution sandbox route is unavailable",
      },
    })
  }
  let provided_token = r.headers.get("x-moonclaw-execution-token").unwrap_or("")
  guard moondesk_sandbox_constant_time_equal(
    provided_token,
    route_config.auth_token,
  ) else {
    raise json_error(401, "Unauthorized", {
      "error": {
        "code": "unauthorized",
        "message": "sandbox route authentication failed",
      },
    })
  }
  let request = moondesk_sandbox_parse_request(moondesk_sandbox_read_request(r)) catch {
    _ =>
      raise json_error(422, "UnprocessableContent", {
        "error": {
          "code": "invalid_request",
          "message": "typed sandbox request was rejected",
        },
      })
  }
  let executor_config = @moonfort_config.load_sandbox_executor_config() catch {
    _ =>
      raise json_error(503, "ServiceUnavailable", {
        "error": {
          "code": "sandbox_unavailable",
          "message": "MoonFort configuration failed closed",
        },
      })
  }
  guard executor_config is Some(executor_config) else {
    raise json_error(503, "ServiceUnavailable", {
      "error": {
        "code": "sandbox_unavailable",
        "message": "MoonFort configuration is unavailable",
      },
    })
  }
  let result = execute_moondesk_moon_diagnostics(
    executor_config, route_config, request,
  ) catch {
    _ =>
      raise json_error(503, "ServiceUnavailable", {
        "error": {
          "code": "sandbox_refused",
          "message": "MoonFort diagnostics execution failed closed",
        },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(result.stringify())
}
