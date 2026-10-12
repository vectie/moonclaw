///|
/// Installed by the trusted analysis runner, never decoded from tool arguments.
pub(all) struct CommandOutputOwner {
  run_id : String
  step_id : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
struct CommandOutputBinding {
  contract_version : Int
  owner : CommandOutputOwner
  audit_id : String
  audit_sha256 : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct BoundCommandOutput {
  output_id : String
  run_id : String
  step_id : String
  status : String
  size_bytes : Int64
  sha256 : String
  expires_at_ms : Int64
  message : String
  receipt_status : String
  exit_code : Int?
  output_truncated : Bool
  limit_reason : String?
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
fn command_output_owner_valid(owner : CommandOutputOwner) -> Bool {
  !owner.run_id.is_blank() &&
  owner.run_id.length() <= 512 &&
  !owner.run_id.contains("\u0000") &&
  owner.step_id.length() <= 512 &&
  !owner.step_id.contains("\u0000")
}

///|
fn command_output_binding_root(
  config : SandboxExecutorConfig,
  run_id : String,
) -> String {
  config.receipt_root + "/command-output/" + sha256_text(run_id)
}

///|
async fn command_output_read_file(path : String, limit : Int) -> String {
  guard @fs.kind(path, follow_symlink=false) is Regular &&
    @fs.realpath(path) == path else {
    fail("Retained command output record is unavailable")
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() is Regular && file.size() <= limit.to_int64() else {
    fail("Output record exceeds its bound")
  }
  let out = @buffer.Buffer(size_hint=4096)
  while file.read_some(max_len=(limit - out.length() + 1).min(8192))
        is Some(chunk) {
    guard out.length() + chunk.length() <= limit else {
      fail("Output record exceeds its bound")
    }
    out.write_bytes(chunk)
  }
  guard @fs.realpath(path) == path &&
    @fs.kind(path, follow_symlink=false) is Regular else {
    fail("Output record changed during reading")
  }
  @utf8.decode(out.to_bytes())
}

///|
fn command_output_audit_valid(audit : SandboxAuditRecord) -> Bool {
  let plan = audit.plan
  let receipt = audit.receipt
  audit.protocol_version == 3 &&
  plan.grant.protocol_version == 3 &&
  safe_identifier(receipt.run_id) &&
  receipt.run_id == plan.grant.request_id &&
  receipt.approval_id == plan.grant.approval_id &&
  receipt.approval_digest == plan.expected_approval_digest &&
  plan.expected_approval_digest == moonfort_grant_digest(plan.grant) &&
  canonical_digest(receipt.command_digest) &&
  receipt.cleanup_verified &&
  (receipt.status is Exited || receipt.status is Killed) &&
  !(receipt.enforcement is Refused)
}

///|
/// Save the link only after the actual execution receipt and audit exist.
/// A deterministic immutable link makes repeat completion safe across reloads.
pub async fn persist_command_output_binding(
  config : SandboxExecutorConfig,
  owner : CommandOutputOwner,
  plan : SandboxApprovalPlan,
  receipt : MoonFortReceipt,
) -> Unit {
  guard command_output_owner_valid(owner) else {
    fail("Command output owner is invalid")
  }
  let audit = SandboxAuditRecord::{ protocol_version: 3, plan, receipt, }
  guard command_output_audit_valid(audit) else {
    fail("Only verified terminal execution can retain a run output link")
  }
  let audit_text = command_output_read_file(
    config.receipt_root + "/" + receipt.run_id + ".json",
    20 * 1024 * 1024,
  )
  let saved : SandboxAuditRecord = @json.from_json(@json.parse(audit_text))
  guard saved == audit else {
    fail("Command output audit changed before run binding")
  }
  let root = command_output_binding_root(config, owner.run_id)
  @fsx.make_directory(root, recursive=true, exists_ok=true)
  guard @fs.realpath(root) == root else {
    fail("Command output binding root is not canonical")
  }
  let binding = CommandOutputBinding::{
    contract_version: 1,
    owner,
    audit_id: receipt.run_id,
    audit_sha256: sha256_text(audit_text),
  }
  let owners = config.receipt_root + "/command-output/owners"
  @fsx.make_directory(owners, recursive=true, exists_ok=true)
  guard @fs.realpath(owners) == owners else {
    fail("Output ownership root is unavailable")
  }
  let ownership = owners + "/" + receipt.run_id + ".json"
  if @fs.exists(ownership) {
    guard command_output_read_file(ownership, 8192) ==
      binding.to_json().stringify() else {
      fail("This execution already belongs to a different run or step")
    }
  } else {
    @fs.write_file(
      ownership,
      binding.to_json().stringify(),
      create_mode=CreateNew,
      permission=0o600,
    )
  }
  let path = root + "/" + receipt.run_id + ".json"
  if @fs.exists(path) {
    guard command_output_read_file(path, 8192) == binding.to_json().stringify() else {
      fail(
        "Command output owner already differs; the original link was retained",
      )
    }
  } else {
    @fs.write_file(
      path,
      binding.to_json().stringify(),
      create_mode=CreateNew,
      permission=0o600,
    )
  }
}

///|
async fn command_output_bound_audit(
  config : SandboxExecutorConfig,
  run_id : String,
  output_id : String,
) -> (CommandOutputOwner, SandboxAuditRecord) {
  guard safe_identifier(output_id) &&
    !run_id.is_blank() &&
    run_id.length() <= 512 else {
    fail("Select an output from this run")
  }
  let root = command_output_binding_root(config, run_id)
  let binding : CommandOutputBinding = @json.from_json(
    @json.parse(
      command_output_read_file(root + "/" + output_id + ".json", 8192),
    ),
  )
  guard binding.contract_version == 1 &&
    binding.owner.run_id == run_id &&
    binding.audit_id == output_id &&
    command_output_owner_valid(binding.owner) else {
    fail("This output is not bound to the selected run")
  }
  guard command_output_read_file(
      config.receipt_root + "/command-output/owners/" + output_id + ".json",
      8192,
    ) ==
    binding.to_json().stringify() else {
    fail("Retained command output ownership failed verification")
  }
  let text = command_output_read_file(
    config.receipt_root + "/" + output_id + ".json",
    20 * 1024 * 1024,
  )
  guard sha256_text(text) == binding.audit_sha256 else {
    fail("Retained execution audit failed verification")
  }
  let audit : SandboxAuditRecord = @json.from_json(@json.parse(text))
  guard command_output_audit_valid(audit) && audit.receipt.run_id == output_id else {
    fail("Retained execution binding failed verification")
  }
  (binding.owner, audit)
}

///|
pub async fn list_bound_command_outputs(
  config : SandboxExecutorConfig,
  run_id : String,
  now_ms : Int64,
) -> Array[BoundCommandOutput] {
  guard !run_id.is_blank() && run_id.length() <= 512 else {
    fail("Run identity is invalid")
  }
  let root = command_output_binding_root(config, run_id)
  if !@fs.exists(root) {
    return []
  }
  guard @fs.realpath(root) == root else {
    fail("Output binding root is unavailable")
  }
  let names = @fs.readdir(root, sort=true)
  guard names.length() <= 4096 else {
    fail("Run has too many retained outputs; use the trusted operator export")
  }
  let result = []
  for name in names {
    if !name.has_suffix(".json") {
      continue
    }
    let id = name[:name.length() - 5].to_owned()
    let (owner, audit) = command_output_bound_audit(config, run_id, id)
    let (status, size_bytes, sha256, expires_at_ms, message) = match
      audit.receipt.output_artifact {
      None =>
        (
          "unavailable", 0L, "", 0L, "This execution did not retain a signed complete-output reference. It cannot be downloaded or reconstructed.",
        )
      Some(reference) if reference.expires_at_ms <= now_ms =>
        (
          "expired",
          reference.size_bytes,
          reference.sha256,
          reference.expires_at_ms,
          "The retained command output has expired. Work will not be rerun.",
        )
      Some(reference) =>
        (
          "available",
          reference.size_bytes,
          reference.sha256,
          reference.expires_at_ms,
          "Exact retained command bytes; downloading never reruns the command.",
        )
    }
    result.push({
      output_id: id,
      run_id,
      step_id: owner.step_id,
      status,
      size_bytes,
      sha256,
      expires_at_ms,
      message,
      receipt_status: match audit.receipt.status {
        Exited => "exited"
        Killed => "killed"
        Failed => "failed"
        Created => "created"
        Running => "running"
      },
      exit_code: audit.receipt.exit_code,
      output_truncated: audit.receipt.output_truncated,
      limit_reason: audit.receipt.limit_reason,
    })
  }
  result
}

///|
pub async fn download_bound_command_output(
  config : SandboxExecutorConfig,
  run_id : String,
  output_id : String,
  now_ms : Int64,
) -> Bytes {
  let (_, audit) = command_output_bound_audit(config, run_id, output_id)
  guard audit.receipt.output_artifact is Some(reference) else {
    fail(
      "This run has no retained signed output reference; it cannot be reconstructed",
    )
  }
  guard reference.expires_at_ms > now_ms else {
    fail("Retained command output has expired; work was not rerun")
  }
  guard moonfort_output_artifact_valid(
      audit.receipt,
      audit.plan.grant.limits.output_bytes,
      now_ms,
    ) &&
    reference.size_bytes <= 64L * 1024L * 1024L else {
    fail("Retained output reference failed verification")
  }
  guard config.command_output_reader_path is Some(path) else {
    fail(
      "The trusted operator has not configured the Fort complete-output reader",
    )
  }
  let client = @sandbox_adapter.CommandOutputClient::new(
    path,
    config.executor_config_path,
    config.receipt_root,
  )
  let request : Json = {
    "protocol_version": 1,
    "reference": reference,
    "run_id": audit.receipt.run_id,
    "approval_digest": audit.receipt.approval_digest,
    "command_digest": audit.receipt.command_digest,
    "offset": 0L.to_json(),
    "max_bytes": reference.size_bytes.to_int().max(1),
  }
  let probe = client.inspect(request.stringify())
  guard probe.status == 0 else {
    fail("Fort output reader is unavailable; retry without rerunning")
  }
  let response = @json.parse(probe.stdout)
  if response is { "error": { "code": String(code), .. }, .. } {
    match code {
      "output-expired" =>
        fail("Retained command output has expired; work was not rerun")
      "output-unavailable" =>
        fail(
          "The retained command output is missing or unavailable; restore it from a trusted backup and retry",
        )
      _ =>
        fail(
          "Fort refused the retained output verification; no bytes were downloaded",
        )
    }
  }
  guard response
    is { "protocol_version": 1, "status": "available", "reference": value, .. } &&
    value == reference.to_json() else {
    fail("Fort returned a mismatched output reference")
  }
  let bytes = client.export(request.stringify(), reference.size_bytes.to_int())
  guard bytes.length().to_int64() == reference.size_bytes &&
    @crypto.bytes_to_hex_string(@crypto.sha256(bytes)) == reference.sha256 else {
    fail("Downloaded output bytes failed verification")
  }
  bytes
}
