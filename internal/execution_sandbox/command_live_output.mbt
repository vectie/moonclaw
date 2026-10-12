///|
// This record is created by the trusted command owner after approval validation,
// before dispatch. It is never inferred from tool results or supplied by HTTP.
struct CommandLiveBinding {
  contract_version : Int
  owner : CommandOutputOwner
  request_id : String
  approval_id : String
  approval_digest : String
  runtime_digest : String
  output_limit : Int
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct BoundCommandLiveOutput {
  output_id : String
  run_id : String
  step_id : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct CommandLiveChunk {
  protocol_version : Int
  output_id : String
  run_id : String
  step_id : String
  stream_id : String
  offset : Int
  next_offset : Int
  available_bytes : Int
  content_base64 : String
  status : String
  terminal : Bool
  retry_after_ms : Int
  next_cursor : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
fn command_live_root(config : SandboxExecutorConfig, run_id : String) -> String {
  config.receipt_root + "/command-live/" + sha256_text(run_id)
}

///|
async fn command_live_write_once(path : String, value : String) -> Unit {
  if @fs.exists(path) {
    guard command_output_read_file(path, 8192) == value else {
      fail("Live output belongs to a different run, step or approved request")
    }
  } else {
    @fs.write_file(
      path,
      value,
      create_mode=CreateNew,
      permission=0o600,
      sync=Full,
    )
  }
}

///|
pub async fn persist_command_live_binding(
  config : SandboxExecutorConfig,
  owner : CommandOutputOwner,
  plan : SandboxApprovalPlan,
) -> Unit {
  guard command_output_owner_valid(owner) &&
    plan.grant.protocol_version == 3 &&
    safe_identifier(plan.grant.request_id) &&
    safe_identifier(plan.grant.approval_id) &&
    plan.expected_approval_digest == moonfort_grant_digest(plan.grant) &&
    plan.runtime_binding_digest == runtime_binding_digest(config) &&
    plan.grant.expires_at_ms > @clock.epoch.now().ms() &&
    plan.grant.limits.output_bytes > 0 &&
    plan.grant.limits.output_bytes <= config.limits.output_bytes else {
    fail("Live output requires a validated unexpired execution approval")
  }
  let root = command_live_root(config, owner.run_id)
  let owners = config.receipt_root + "/command-live/owners"
  @fsx.make_directory(root, recursive=true, exists_ok=true)
  @fsx.make_directory(owners, recursive=true, exists_ok=true)
  guard @fs.realpath(root) == root && @fs.realpath(owners) == owners else {
    fail("Live output ownership root is unavailable")
  }
  let binding = CommandLiveBinding::{
    contract_version: 1,
    owner,
    request_id: plan.grant.request_id,
    approval_id: plan.grant.approval_id,
    approval_digest: plan.expected_approval_digest,
    runtime_digest: plan.runtime_binding_digest,
    output_limit: plan.grant.limits.output_bytes,
  }
  let value = binding.to_json().stringify()
  // Both identities are globally single-owner, including retries/restarts.
  command_live_write_once(
    owners + "/request-" + binding.request_id + ".json",
    value,
  )
  command_live_write_once(
    owners + "/approval-" + binding.approval_id + ".json",
    value,
  )
  command_live_write_once(root + "/" + binding.request_id + ".json", value)
}

///|
async fn command_live_binding(
  config : SandboxExecutorConfig,
  run_id : String,
  output_id : String,
) -> CommandLiveBinding {
  guard safe_identifier(output_id) &&
    command_output_owner_valid({ run_id, step_id: "", }) else {
    fail("Select a live output from this run")
  }
  let binding : CommandLiveBinding = @json.from_json(
    @json.parse(
      command_output_read_file(
        command_live_root(config, run_id) + "/" + output_id + ".json",
        8192,
      ),
    ),
  )
  guard binding.contract_version == 1 &&
    binding.owner.run_id == run_id &&
    command_output_owner_valid(binding.owner) &&
    binding.request_id == output_id &&
    safe_identifier(binding.approval_id) &&
    canonical_digest(binding.approval_digest) &&
    binding.runtime_digest == runtime_binding_digest(config) &&
    binding.output_limit > 0 &&
    binding.output_limit <= config.limits.output_bytes else {
    fail("Live output ownership failed verification")
  }
  let owners = config.receipt_root + "/command-live/owners/"
  let value = binding.to_json().stringify()
  guard command_output_read_file(
      owners + "request-" + output_id + ".json",
      8192,
    ) ==
    value &&
    command_output_read_file(
      owners + "approval-" + binding.approval_id + ".json",
      8192,
    ) ==
    value else {
    fail("Live output ownership failed verification")
  }
  binding
}

///|
pub async fn list_bound_command_live_outputs(
  config : SandboxExecutorConfig,
  run_id : String,
) -> Array[BoundCommandLiveOutput] {
  guard command_output_owner_valid({ run_id, step_id: "", }) else {
    fail("Invalid run")
  }
  let root = command_live_root(config, run_id)
  if !@fs.exists(root) {
    return []
  }
  guard @fs.realpath(root) == root else {
    fail("Live output ownership root is unavailable")
  }
  let names = @fs.readdir(root, sort=true)
  guard names.length() <= 4096 else { fail("Too many live output records") }
  let result = []
  for name in names {
    if !name.has_suffix(".json") {
      continue
    }
    let binding = command_live_binding(
      config,
      run_id,
      name[:name.length() - 5].to_owned(),
    )
    result.push({
      output_id: binding.request_id,
      run_id,
      step_id: binding.owner.step_id,
    })
  }
  result
}

///|
fn validated_live_output_bytes(
  response : MoonFortLiveOutputReadResponse,
  approval_id : String,
  request_id : String,
  offset : Int64,
  output_limit : Int,
) -> Bytes raise {
  guard response.error is None &&
    response.protocol_version == 1 &&
    response.approval_id == approval_id &&
    response.run_id == request_id &&
    canonical_digest(response.stream_id) &&
    response.offset == offset &&
    offset >= 0L &&
    response.next_offset >= offset &&
    response.next_offset <= response.available_bytes &&
    response.available_bytes <= output_limit.to_int64() &&
    response.available_bytes <= 67108864L &&
    response.next_offset - offset <= 65536L &&
    response.content_base64.length() <= 87384 &&
    ["running", "exited", "killed", "failed"].contains(response.status) &&
    response.terminal ==
    (
      response.status != "running" &&
      response.next_offset == response.available_bytes
    ) &&
    response.retry_after_ms >= 0 &&
    response.retry_after_ms <= 5000 else {
    fail("Live output response failed verification")
  }
  let bytes = @base64.decode(response.content_base64) catch {
    _ => fail("Live output bytes failed verification")
  }
  guard bytes.length().to_int64() == response.next_offset - offset &&
    @base64.encode(bytes) == response.content_base64 else {
    fail("Live output byte length failed verification")
  }
  bytes
}

///|
pub async fn read_bound_command_live_output(
  config : SandboxExecutorConfig,
  run_id : String,
  output_id : String,
  cursor : String,
) -> CommandLiveChunk {
  let binding = command_live_binding(config, run_id, output_id)
  guard config.live_output_reader_path is Some(_) else {
    fail("The trusted operator has not configured the Fort live-output reader")
  }
  let (expected_stream, offset) = if cursor == "start" {
    (None, 0L)
  } else {
    let parts = cursor.split(":").to_array()
    guard parts.length() == 2 && canonical_digest(parts[0].to_owned()) else {
      fail("Live output cursor failed verification")
    }
    let offset = @string.parse_int64(parts[1]) catch {
      _ => fail("Live output cursor failed verification")
    }
    guard offset >= 0L &&
      offset <= binding.output_limit.to_int64() &&
      offset.to_string() == parts[1].to_owned() else {
      fail("Live output cursor failed verification")
    }
    (Some(parts[0].to_owned()), offset)
  }
  let client = @sandbox_adapter.Client::new(
    config.grant_publisher_path,
    config.grant_publisher_args,
    config.executor_path,
    config.executor_args,
    config.executor_config_path,
    config.receipt_root,
    live_output_reader_path?=config.live_output_reader_path,
    live_output_reader_args=config.live_output_reader_args.unwrap_or([]),
  )
  let request : Json = {
    "protocol_version": 1,
    "approval_id": binding.approval_id,
    "offset": offset,
    "max_bytes": 65536,
  }
  guard client.read_live_output(request.stringify() + "\n") is Some(process) &&
    process.status == 0 else {
    fail("Live output reader is unavailable")
  }
  let response : MoonFortLiveOutputReadResponse = @json.from_json(
    @json.parse(process.stdout),
  )
  if response.error is Some(error) {
    if error.code == "live-output-integrity-refused" {
      fail("Live output expired or failed verification")
    }
    fail("Live output has not started, or the retained spool is unavailable")
  }
  ignore(
    validated_live_output_bytes(
      response,
      binding.approval_id,
      output_id,
      offset,
      binding.output_limit,
    ),
  )
  if expected_stream is Some(stream) && stream != response.stream_id {
    fail("Live output stream changed; cursor refused")
  }
  // Persist only the identity, never a copy of the stream. This survives gateway
  // restarts and prevents a reader replacement from silently changing streams.
  command_live_write_once(
    command_live_root(config, run_id) + "/" + output_id + ".stream",
    response.stream_id,
  )
  {
    protocol_version: 1,
    output_id,
    run_id,
    step_id: binding.owner.step_id,
    stream_id: response.stream_id,
    offset: response.offset.to_int(),
    next_offset: response.next_offset.to_int(),
    available_bytes: response.available_bytes.to_int(),
    content_base64: response.content_base64,
    status: response.status,
    terminal: response.terminal,
    retry_after_ms: response.retry_after_ms.max(100),
    next_cursor: response.stream_id + ":" + response.next_offset.to_string(),
  }
}
