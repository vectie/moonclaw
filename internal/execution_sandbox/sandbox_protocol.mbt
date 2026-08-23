///|
/// These types mirror MoonFort protocol v3. MoonClaw publishes a single-use grant
/// into the trusted pending store, while the executor accepts only an opaque
/// approval ID over stdin.
pub(all) enum MoonFortBackendKind {
  LocalOs
  MicroVm
  Unavailable
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) enum MoonFortNetworkMode {
  Deny
  AllowList
  Unrestricted
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) enum MoonFortEnforcementRequirement {
  RequireEnforced
  AllowDegraded
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) enum MoonFortEnforcement {
  Enforced
  Degraded
  Refused
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) enum MoonFortRunStatus {
  Created
  Running
  Exited
  Killed
  Failed
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) enum MoonFortScratchEntryKind {
  RegularFile
  DirectoryEntry
  SymbolicLink
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) enum MoonFortScratchChangeKind {
  Added
  Modified
  Removed
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct MoonFortScratchEntry {
  relative_path : String
  kind : MoonFortScratchEntryKind
  size_bytes : Int64
  fingerprint : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct MoonFortScratchChange {
  relative_path : String
  change : MoonFortScratchChangeKind
  before : MoonFortScratchEntry?
  after : MoonFortScratchEntry?
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct MoonFortLimits {
  wall_clock_ms : Int
  cpu_seconds : Int
  memory_mib : Int
  disk_mib : Int
  processes : Int
  output_bytes : Int
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) enum MoonFortCommand {
  Exec(tool~ : String, args~ : Array[String])
  Shell(script~ : String)
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct MoonFortExecutionGrant {
  protocol_version : Int
  approval_id : String
  request_id : String
  workspace_id : String
  backend : MoonFortBackendKind
  enforcement_requirement : MoonFortEnforcementRequirement
  network : MoonFortNetworkMode
  allowed_egress : Array[String]
  allowed_commands : Array[String]
  limits : MoonFortLimits
  working_directory : String
  command : MoonFortCommand
  backend_config_id : String
  expires_at_ms : Int64
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
struct MoonFortInvocation {
  protocol_version : Int
  approval_id : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
struct MoonFortGrantPublicationRequest {
  protocol_version : Int
  grant : MoonFortExecutionGrant
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
struct MoonFortGrantPublicationResponse {
  protocol_version : Int
  approval_id : String
  approval_digest : String
  published : Bool
  error : MoonFortProtocolError?
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
/// Opaque executor-owned reference to the complete merged command output.
/// MoonClaw validates the public metadata but never interprets `artifact_id`
/// as a path. Content and signature verification remain the responsibility of
/// MoonFort's fixed artifact-reader capability.
pub(all) struct MoonFortCommandOutputArtifactRef {
  artifact_id : String
  run_id : String
  sha256 : String
  size_bytes : Int64
  media_type : String
  expires_at_ms : Int64
  key_id : String
  signature : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct MoonFortReceipt {
  run_id : String
  approval_id : String
  approval_digest : String
  command_digest : String
  backend : MoonFortBackendKind
  enforcement : MoonFortEnforcement
  status : MoonFortRunStatus
  profile_digest : String
  exit_code : Int?
  output : String
  output_truncated : Bool
  /// Present whenever the approved hard output ceiling was reached, and also
  /// when MoonFort projected otherwise complete output down to its configured
  /// model-facing budget. Missing fields from older small-output receipts
  /// decode as `None` for wire compatibility.
  output_artifact : MoonFortCommandOutputArtifactRef?
  limit_reason : String?
  /// Limits the selected backend could not independently prove hard. An
  /// enforced backend returns an empty array; degraded local execution must
  /// enumerate its residual guarantees explicitly.
  unverified_limits : Array[String]
  changed_paths : Array[String]
  changes : Array[MoonFortScratchChange]
  artifacts : Array[String]
  denial_reason : String?
  cleanup_verified : Bool
  retention_id : String?
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
struct MoonFortProtocolError {
  code : String
  message : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
struct MoonFortExecutorResponse {
  protocol_version : Int
  approval_id : String
  receipt : MoonFortReceipt?
  error : MoonFortProtocolError?
  live_output : MoonFortLiveOutputReference?
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct MoonFortLiveOutputReference {
  stream_id : String
  run_id : String
  status : String
  size_bytes : Int64
  sha256 : String
  expires_at_ms : Int64
  key_id : String
  signature : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
struct MoonFortLiveOutputReadResponse {
  protocol_version : Int
  approval_id : String
  stream_id : String
  run_id : String
  offset : Int64
  next_offset : Int64
  available_bytes : Int64
  content_base64 : String
  status : String
  terminal : Bool
  retry_after_ms : Int
  error : MoonFortProtocolError?
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub(all) struct SandboxExecutorConfig {
  /// Canonical absolute path to the trusted MoonFort grant publisher.
  grant_publisher_path : String
  /// Fixed operator-controlled publisher arguments.
  grant_publisher_args : Array[String]
  /// Canonical absolute path to the trusted MoonFort one-shot executor.
  executor_path : String
  /// Fixed operator-controlled arguments. Tool input can never add arguments.
  executor_args : Array[String]
  live_output_reader_path : String?
  live_output_reader_args : Array[String]?
  /// Canonical regular file loaded by MoonFort through its sole config env var.
  executor_config_path : String
  /// Canonical MoonClaw-owned directory for terminal audit records.
  receipt_root : String
  /// Opaque keys into the executor-owned workspace and backend registries.
  workspace_id : String
  backend_config_id : String
  backend : MoonFortBackendKind
  enforcement_requirement : MoonFortEnforcementRequirement
  network : MoonFortNetworkMode
  allowed_egress : Array[String]
  allowed_commands : Array[String]
  limits : MoonFortLimits
  grant_ttl_ms : Int64
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
pub fn local_sandbox_executor_config(
  grant_publisher_path : String,
  executor_path : String,
  executor_config_path : String,
  receipt_root : String,
  workspace_id : String,
  allow_degraded? : Bool = false,
) -> SandboxExecutorConfig {
  {
    grant_publisher_path,
    grant_publisher_args: [],
    executor_path,
    executor_args: [],
    live_output_reader_path: None,
    live_output_reader_args: None,
    executor_config_path,
    receipt_root,
    workspace_id,
    backend_config_id: "local",
    backend: LocalOs,
    enforcement_requirement: if allow_degraded {
      AllowDegraded
    } else {
      RequireEnforced
    },
    network: Deny,
    allowed_egress: [],
    allowed_commands: ["shell-compat"],
    limits: {
      wall_clock_ms: 120_000,
      cpu_seconds: 60,
      memory_mib: 1_024,
      disk_mib: 2_048,
      processes: 256,
      output_bytes: 10 * 1024 * 1024,
    },
    // Covers the daemon's maximum human approval wait while remaining
    // short-lived. The executor still consumes the grant exactly once.
    grant_ttl_ms: 900_000L,
  }
}

///|
pub(all) struct SandboxApprovalPlan {
  grant : MoonFortExecutionGrant
  expected_approval_digest : String
  runtime_binding_digest : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
struct SandboxAuditRecord {
  protocol_version : Int
  plan : SandboxApprovalPlan
  receipt : MoonFortReceipt
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
fn sha256_text(text : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(text)))
}

///|
pub fn moonfort_grant_digest(grant : MoonFortExecutionGrant) -> String {
  let allowed_egress = grant.allowed_egress.copy()
  let allowed_commands = grant.allowed_commands.copy()
  allowed_egress.sort()
  allowed_commands.sort()
  let canonical = { ..grant, allowed_egress, allowed_commands }
  sha256_text(canonical.to_json().stringify())
}

///|
fn runtime_binding_digest(config : SandboxExecutorConfig) -> String {
  sha256_text(
    (
      {
        "grant_publisher_path": config.grant_publisher_path,
        "grant_publisher_args": config.grant_publisher_args,
        "executor_path": config.executor_path,
        "executor_args": config.executor_args,
        "live_output_reader_path": config.live_output_reader_path,
        "live_output_reader_args": config.live_output_reader_args,
        "executor_config_path": config.executor_config_path,
        "workspace_id": config.workspace_id,
        "backend_config_id": config.backend_config_id,
        "backend": config.backend,
        "enforcement_requirement": config.enforcement_requirement,
        "network": config.network,
        "allowed_egress": config.allowed_egress,
        "allowed_commands": config.allowed_commands,
        "limits": config.limits,
        "grant_ttl_ms": config.grant_ttl_ms,
      } : Json).stringify(),
  )
}

///|
fn canonical_absolute_path(path : String) -> Bool {
  path.has_prefix("/") &&
  !path.contains("//") &&
  !path.contains("\u{0}") &&
  !path.split("/").any(component => component == "." || component == "..") &&
  (path == "/" || !path.has_suffix("/"))
}

///|
const MoonFortCommandOutputMediaType : String = "text/plain; charset=utf-8"

///|
/// Validate only the artifact properties available at the MoonClaw protocol
/// boundary. MoonFort's trusted artifact reader must still authenticate the
/// signature and recheck the manifest, file identity, size, and content hash
/// before returning any bytes.
pub fn moonfort_output_artifact_valid(
  receipt : MoonFortReceipt,
  output_limit : Int,
  now_ms : Int64,
) -> Bool {
  let terminal_output = receipt.status is Exited || receipt.status is Killed
  match receipt.output_artifact {
    None => !receipt.output_truncated || !terminal_output
    Some(reference) =>
      terminal_output &&
      output_limit > 0 &&
      safe_identifier(reference.artifact_id) &&
      safe_identifier(reference.run_id) &&
      reference.run_id == receipt.run_id &&
      canonical_digest(reference.sha256) &&
      reference.size_bytes >= 0L &&
      reference.size_bytes <= output_limit.to_int64() &&
      reference.size_bytes >= @utf8.encode(receipt.output).length().to_int64() &&
      reference.media_type == MoonFortCommandOutputMediaType &&
      reference.expires_at_ms > now_ms &&
      safe_identifier(reference.key_id) &&
      canonical_digest(reference.signature)
  }
}

///|
/// Validate the terminal live-output capability without interpreting its
/// opaque stream identifier. MoonFort's fixed reader remains responsible for
/// authenticating the signature and the executor-owned manifest on every
/// read.
pub fn moonfort_live_output_reference_valid(
  reference : MoonFortLiveOutputReference,
  receipt : MoonFortReceipt,
  output_limit : Int,
  now_ms : Int64,
) -> Bool {
  let expected_status = match receipt.status {
    Exited => "exited"
    Killed => "killed"
    Failed => "failed"
    Created => "created"
    Running => "running"
  }
  output_limit > 0 &&
  safe_identifier(reference.stream_id) &&
  safe_identifier(reference.run_id) &&
  reference.run_id == receipt.run_id &&
  reference.status == expected_status &&
  reference.size_bytes >= 0L &&
  reference.size_bytes <= output_limit.to_int64() &&
  reference.size_bytes >= @utf8.encode(receipt.output).length().to_int64() &&
  canonical_digest(reference.sha256) &&
  reference.expires_at_ms > now_ms &&
  safe_identifier(reference.key_id) &&
  canonical_digest(reference.signature)
}

///|
fn safe_identifier(value : String) -> Bool {
  value.length() >= 1 &&
  value.length() <= 128 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_'
  })
}

///|
fn secure_identifier(prefix : String) -> String raise {
  guard @env.rand(16) is Some(random) else {
    fail("secure randomness is unavailable")
  }
  "\{prefix}-\{@crypto.bytes_to_hex_string(random)}"
}

///|
fn relative_directory(
  workspace_root : String,
  working_directory : String,
) -> String raise {
  if working_directory == workspace_root {
    ""
  } else if working_directory.has_prefix(workspace_root + "/") {
    working_directory[workspace_root.length() + 1:].to_owned()
  } else {
    fail("working_directory resolves outside the canonical workspace")
  }
}

///|
async fn validate_operator_config(config : SandboxExecutorConfig) -> Unit {
  guard canonical_absolute_path(config.grant_publisher_path) &&
    @fsx.resolve(config.grant_publisher_path) == config.grant_publisher_path &&
    @fsx.exists_as_file(config.grant_publisher_path) else {
    fail("MoonFort grant_publisher_path must be a canonical regular file")
  }
  guard canonical_absolute_path(config.executor_path) &&
    @fsx.resolve(config.executor_path) == config.executor_path else {
    fail("MoonFort executor_path must be canonical and absolute")
  }
  match config.live_output_reader_path {
    Some(path) => {
      let valid = canonical_absolute_path(path) &&
        @fsx.resolve(path) == path &&
        @fsx.exists_as_file(path) &&
        config.live_output_reader_args.unwrap_or([]).length() <= 16
      guard valid else {
        fail("MoonFort live output reader configuration is invalid")
      }
    }
    None => ()
  }
  guard canonical_absolute_path(config.executor_config_path) &&
    @fsx.resolve(config.executor_config_path) == config.executor_config_path &&
    @fsx.exists_as_file(config.executor_config_path) else {
    fail("MoonFort executor_config_path must be a canonical regular file")
  }
  guard canonical_absolute_path(config.receipt_root) &&
    @fsx.resolve(config.receipt_root) == config.receipt_root else {
    fail("MoonFort receipt_root must be canonical and absolute")
  }
  guard safe_identifier(config.workspace_id) &&
    safe_identifier(config.backend_config_id) else {
    fail("MoonFort registry identifiers are invalid")
  }
  guard config.limits.wall_clock_ms > 0 &&
    config.limits.cpu_seconds > 0 &&
    config.limits.memory_mib > 0 &&
    config.limits.disk_mib > 0 &&
    config.limits.processes > 0 &&
    config.limits.output_bytes > 0 &&
    config.grant_ttl_ms > 0L else {
    fail("MoonFort grant limits must be positive")
  }
}

///|
pub async fn make_sandbox_plan(
  config : SandboxExecutorConfig,
  workspace : String,
  working_directory : String,
  command : String,
  timeout_ms : Int,
) -> SandboxApprovalPlan {
  validate_operator_config(config)
  guard config.allowed_commands.contains("shell-compat") else {
    fail("legacy shell commands require the explicit shell-compat capability")
  }
  let workspace_root = @fsx.resolve(workspace)
  let canonical_working_directory = @fsx.resolve(working_directory)
  let relative = relative_directory(workspace_root, canonical_working_directory)
  let now_ms = @clock.epoch.now().ms()
  let grant = MoonFortExecutionGrant::{
    protocol_version: 3,
    approval_id: secure_identifier("approval"),
    request_id: secure_identifier("run"),
    workspace_id: config.workspace_id,
    backend: config.backend,
    enforcement_requirement: config.enforcement_requirement,
    network: config.network,
    allowed_egress: config.allowed_egress.copy(),
    allowed_commands: ["shell-compat"],
    limits: { ..config.limits, wall_clock_ms: timeout_ms },
    working_directory: relative,
    command: Shell(script=command),
    backend_config_id: config.backend_config_id,
    expires_at_ms: now_ms + config.grant_ttl_ms,
  }
  {
    grant,
    expected_approval_digest: moonfort_grant_digest(grant),
    runtime_binding_digest: runtime_binding_digest(config),
  }
}

///|
/// Build a grant for one operator-configured executable capability. The
/// executable itself is never supplied by the caller: `tool` is only the
/// capability label resolved by MoonFort's trusted registry.
pub async fn make_exec_plan(
  config : SandboxExecutorConfig,
  workspace : String,
  working_directory : String,
  tool : String,
  args : Array[String],
  timeout_ms : Int,
) -> SandboxApprovalPlan {
  validate_operator_config(config)
  guard safe_identifier(tool) && config.allowed_commands.contains(tool) else {
    fail("MoonFort configuration does not allow the requested capability")
  }
  guard args.length() <= 256 &&
    args.all(arg => {
      !arg.contains("\u{0}") && @utf8.encode(arg).length() <= 65_536
    }) else {
    fail("MoonFort command arguments exceed the MoonClaw transport bound")
  }
  let workspace_root = @fsx.resolve(workspace)
  let canonical_working_directory = @fsx.resolve(working_directory)
  let relative = relative_directory(workspace_root, canonical_working_directory)
  let now_ms = @clock.epoch.now().ms()
  let grant = MoonFortExecutionGrant::{
    protocol_version: 3,
    approval_id: secure_identifier("approval"),
    request_id: secure_identifier("run"),
    workspace_id: config.workspace_id,
    backend: config.backend,
    enforcement_requirement: config.enforcement_requirement,
    network: config.network,
    allowed_egress: config.allowed_egress.copy(),
    allowed_commands: [tool],
    limits: { ..config.limits, wall_clock_ms: timeout_ms },
    working_directory: relative,
    command: Exec(tool~, args=args.copy()),
    backend_config_id: config.backend_config_id,
    expires_at_ms: now_ms + config.grant_ttl_ms,
  }
  {
    grant,
    expected_approval_digest: moonfort_grant_digest(grant),
    runtime_binding_digest: runtime_binding_digest(config),
  }
}

///|
fn moon_check_arguments(target : String) -> Array[String] raise {
  guard target == "" ||
    target == "wasm" ||
    target == "wasm-gc" ||
    target == "js" ||
    target == "native" ||
    target == "llvm" ||
    target == "all" else {
    fail("unsupported moon check target")
  }
  if target == "" {
    ["check"]
  } else {
    ["check", "--target", target]
  }
}

///|
fn moon_diagnostics_arguments(target : String) -> Array[String] raise {
  let base = moon_check_arguments(target)
  base + ["--output-json", "--diagnostic-limit", "1000"]
}

///|
pub async fn make_moon_check_plan(
  config : SandboxExecutorConfig,
  workspace : String,
  working_directory : String,
  target : String,
  timeout_ms : Int,
) -> SandboxApprovalPlan {
  validate_operator_config(config)
  guard config.allowed_commands.contains("moon") else {
    fail("MoonFort configuration does not allow the moon capability")
  }
  let workspace_root = @fsx.resolve(workspace)
  let canonical_working_directory = @fsx.resolve(working_directory)
  let relative = relative_directory(workspace_root, canonical_working_directory)
  let now_ms = @clock.epoch.now().ms()
  let grant = MoonFortExecutionGrant::{
    protocol_version: 3,
    approval_id: secure_identifier("approval"),
    request_id: secure_identifier("run"),
    workspace_id: config.workspace_id,
    backend: config.backend,
    enforcement_requirement: config.enforcement_requirement,
    network: config.network,
    allowed_egress: config.allowed_egress.copy(),
    allowed_commands: ["moon"],
    limits: { ..config.limits, wall_clock_ms: timeout_ms },
    working_directory: relative,
    command: Exec(tool="moon", args=moon_check_arguments(target)),
    backend_config_id: config.backend_config_id,
    expires_at_ms: now_ms + config.grant_ttl_ms,
  }
  {
    grant,
    expected_approval_digest: moonfort_grant_digest(grant),
    runtime_binding_digest: runtime_binding_digest(config),
  }
}

///|
pub async fn make_moon_diagnostics_plan(
  config : SandboxExecutorConfig,
  workspace : String,
  working_directory : String,
  target : String,
  timeout_ms : Int,
) -> SandboxApprovalPlan {
  validate_operator_config(config)
  guard config.allowed_commands.contains("moon") else {
    fail("MoonFort configuration does not allow the moon capability")
  }
  let workspace_root = @fsx.resolve(workspace)
  let canonical_working_directory = @fsx.resolve(working_directory)
  let relative = relative_directory(workspace_root, canonical_working_directory)
  let now_ms = @clock.epoch.now().ms()
  let grant = MoonFortExecutionGrant::{
    protocol_version: 3,
    approval_id: secure_identifier("approval"),
    request_id: secure_identifier("run"),
    workspace_id: config.workspace_id,
    backend: config.backend,
    enforcement_requirement: config.enforcement_requirement,
    network: config.network,
    allowed_egress: config.allowed_egress.copy(),
    allowed_commands: ["moon"],
    limits: { ..config.limits, wall_clock_ms: timeout_ms },
    working_directory: relative,
    command: Exec(tool="moon", args=moon_diagnostics_arguments(target)),
    backend_config_id: config.backend_config_id,
    expires_at_ms: now_ms + config.grant_ttl_ms,
  }
  {
    grant,
    expected_approval_digest: moonfort_grant_digest(grant),
    runtime_binding_digest: runtime_binding_digest(config),
  }
}

///|
pub fn approved_plan(
  record : @security.ApprovalRecord,
) -> SandboxApprovalPlan raise {
  guard record.context is Some(context) else {
    fail("approval is not bound to a MoonFort execution grant")
  }
  @json.from_json(context)
}

///|
pub async fn validate_approved_plan(
  plan : SandboxApprovalPlan,
  config : SandboxExecutorConfig,
  expected_workspace : String,
  expected_working_directory : String,
  expected_command : String,
) -> Unit {
  guard plan.expected_approval_digest == moonfort_grant_digest(plan.grant) else {
    fail("approved MoonFort grant digest is invalid")
  }
  guard plan.runtime_binding_digest == runtime_binding_digest(config) else {
    fail("MoonFort operator configuration changed after approval")
  }
  guard plan.grant.expires_at_ms > @clock.epoch.now().ms() else {
    fail("approved MoonFort grant expired")
  }
  let workspace = @fsx.resolve(expected_workspace)
  let working_directory = @fsx.resolve(expected_working_directory)
  let relative = relative_directory(workspace, working_directory)
  guard plan.grant.working_directory == relative &&
    plan.grant.command is Shell(script~) &&
    script == expected_command else {
    fail("approved MoonFort command does not match the requested command")
  }
}

///|
pub async fn validate_exec_plan(
  plan : SandboxApprovalPlan,
  config : SandboxExecutorConfig,
  expected_workspace : String,
  expected_working_directory : String,
  expected_tool : String,
  expected_args : Array[String],
) -> Unit {
  guard plan.expected_approval_digest == moonfort_grant_digest(plan.grant) else {
    fail("approved MoonFort grant digest is invalid")
  }
  guard plan.runtime_binding_digest == runtime_binding_digest(config) else {
    fail("MoonFort operator configuration changed after approval")
  }
  guard plan.grant.expires_at_ms > @clock.epoch.now().ms() else {
    fail("approved MoonFort grant expired")
  }
  let workspace = @fsx.resolve(expected_workspace)
  let working_directory = @fsx.resolve(expected_working_directory)
  let relative = relative_directory(workspace, working_directory)
  guard plan.grant.working_directory == relative &&
    plan.grant.command is Exec(tool~, args~) &&
    tool == expected_tool &&
    args == expected_args else {
    fail("approved MoonFort executable command does not match the request")
  }
}

///|
pub async fn validate_moon_check_plan(
  plan : SandboxApprovalPlan,
  config : SandboxExecutorConfig,
  expected_workspace : String,
  expected_working_directory : String,
  expected_target : String,
) -> Unit {
  guard plan.expected_approval_digest == moonfort_grant_digest(plan.grant) else {
    fail("approved MoonFort grant digest is invalid")
  }
  guard plan.runtime_binding_digest == runtime_binding_digest(config) else {
    fail("MoonFort operator configuration changed after approval")
  }
  guard plan.grant.expires_at_ms > @clock.epoch.now().ms() else {
    fail("approved MoonFort grant expired")
  }
  let workspace = @fsx.resolve(expected_workspace)
  let working_directory = @fsx.resolve(expected_working_directory)
  let relative = relative_directory(workspace, working_directory)
  let expected_args = moon_check_arguments(expected_target)
  guard plan.grant.working_directory == relative &&
    plan.grant.command is Exec(tool~, args~) &&
    tool == "moon" &&
    args == expected_args else {
    fail("approved MoonFort moon check command does not match the request")
  }
}

///|
pub async fn validate_moon_diagnostics_plan(
  plan : SandboxApprovalPlan,
  config : SandboxExecutorConfig,
  expected_workspace : String,
  expected_working_directory : String,
  expected_target : String,
) -> Unit {
  guard plan.expected_approval_digest == moonfort_grant_digest(plan.grant) else {
    fail("approved MoonFort grant digest is invalid")
  }
  guard plan.runtime_binding_digest == runtime_binding_digest(config) else {
    fail("MoonFort operator configuration changed after approval")
  }
  guard plan.grant.expires_at_ms > @clock.epoch.now().ms() else {
    fail("approved MoonFort grant expired")
  }
  let workspace = @fsx.resolve(expected_workspace)
  let working_directory = @fsx.resolve(expected_working_directory)
  let relative = relative_directory(workspace, working_directory)
  let expected_args = moon_diagnostics_arguments(expected_target)
  guard plan.grant.working_directory == relative &&
    plan.grant.command is Exec(tool~, args~) &&
    tool == "moon" &&
    args == expected_args else {
    fail(
      "approved MoonFort moon diagnostics command does not match the request",
    )
  }
}

///|
async fn publish_pending_grant(
  client : @sandbox_adapter.Client,
  plan : SandboxApprovalPlan,
) -> Unit {
  let request : MoonFortGrantPublicationRequest = {
    protocol_version: 3,
    grant: plan.grant,
  }
  let process = client.publish_grant(request.to_json().stringify() + "\n")
  guard process.status == 0 else {
    fail("MoonFort grant publisher exited with status \{process.status}")
  }
  let response : MoonFortGrantPublicationResponse = @json.from_json(
    @json.parse(process.stdout),
  ) catch {
    _ => fail("MoonFort grant publisher returned an invalid response")
  }
  guard response.protocol_version == 3 &&
    response.published &&
    response.error is None &&
    response.approval_id == plan.grant.approval_id &&
    response.approval_digest == plan.expected_approval_digest else {
    fail("MoonFort grant publisher refused or mismatched the approved grant")
  }
}

///|
fn canonical_digest(value : String) -> Bool {
  value.length() == 64 &&
  value.all(character => {
    character.is_ascii_digit() || (character >= 'a' && character <= 'f')
  })
}

///|
pub async fn invoke_moonfort(
  config : SandboxExecutorConfig,
  plan : SandboxApprovalPlan,
  live_output_progress? : async (Int64, Bool) -> Unit,
) -> MoonFortReceipt {
  validate_operator_config(config)
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
  publish_pending_grant(client, plan)
  let invocation = MoonFortInvocation::{
    protocol_version: 3,
    approval_id: plan.grant.approval_id,
  }
  let transport_timeout = plan.grant.limits.wall_clock_ms + 5_000
  let process = if live_output_progress is Some(progress) &&
    config.live_output_reader_path is Some(_) {
    @async.with_task_group(group => {
      let done = Ref(false)
      let offset = Ref(0L)
      let executor = group.spawn(
        () => {
          client.invoke_executor(
            invocation.to_json().stringify() + "\n",
            transport_timeout,
          )
        },
        no_wait=true,
      )
      group.spawn_bg(
        () => {
          while !done.val {
            match
              client.read_live_output(
                (
                  {
                    "protocol_version": 1,
                    "approval_id": plan.grant.approval_id,
                    "offset": offset.val,
                    "max_bytes": 65536,
                  } : Json).stringify() +
                "\n",
              ) {
              Some(reader) if reader.status == 0 => {
                let response : MoonFortLiveOutputReadResponse = @json.from_json(
                  @json.parse(reader.stdout),
                ) catch {
                  _ => {
                    @async.sleep(100)
                    continue
                  }
                }
                if response.error is None && response.next_offset >= offset.val {
                  offset.val = response.next_offset
                  progress(response.available_bytes, response.terminal)
                }
              }
              _ => ()
            }
            @async.sleep(100)
          }
        },
        no_wait=true,
        allow_failure=true,
      )
      let result = executor.wait()
      done.val = true
      result
    })
  } else {
    client.invoke_executor(
      invocation.to_json().stringify() + "\n",
      transport_timeout,
    )
  }
  guard process.status == 0 else {
    fail("MoonFort executor exited with status \{process.status}")
  }
  let response : MoonFortExecutorResponse = @json.from_json(
    @json.parse(process.stdout),
  )
  guard response.protocol_version == 3 else {
    fail("MoonFort returned an unsupported protocol version")
  }
  guard response.approval_id == plan.grant.approval_id else {
    fail("MoonFort response approval ID does not match the consumed grant")
  }
  guard response.error is None else {
    let error = response.error.unwrap()
    fail("MoonFort executor refused the invocation (\{error.code})")
  }
  guard response.receipt is Some(receipt) else {
    fail("MoonFort response omitted its terminal receipt")
  }
  guard receipt.run_id == plan.grant.request_id &&
    receipt.approval_id == plan.grant.approval_id &&
    receipt.approval_digest == plan.expected_approval_digest &&
    receipt.backend == plan.grant.backend &&
    canonical_digest(receipt.command_digest) &&
    canonical_digest(receipt.profile_digest) else {
    fail("MoonFort receipt does not match the approved grant")
  }
  guard @utf8.encode(receipt.output).length() <= plan.grant.limits.output_bytes else {
    fail("MoonFort inline output exceeds the approved output ceiling")
  }
  guard !(receipt.enforcement is Refused) else {
    let reason = receipt.denial_reason.unwrap_or("unspecified refusal")
    fail("MoonFort refused execution: \{reason}")
  }
  if plan.grant.enforcement_requirement is RequireEnforced {
    guard receipt.enforcement is Enforced else {
      fail("MoonFort did not provide the required enforced boundary")
    }
  }
  guard receipt.cleanup_verified else {
    fail("MoonFort did not verify descendant and scratch cleanup")
  }
  if receipt.enforcement is Enforced {
    guard receipt.unverified_limits.is_empty() else {
      fail("MoonFort enforced receipt contains unverified limits")
    }
  } else if receipt.enforcement is Degraded {
    guard !receipt.unverified_limits.is_empty() else {
      fail("MoonFort degraded receipt omitted its unverified limits")
    }
  }
  guard moonfort_output_artifact_valid(
    receipt,
    plan.grant.limits.output_bytes,
    @clock.epoch.now().ms(),
  ) else {
    fail("MoonFort output artifact metadata is invalid or incomplete")
  }
  match response.live_output {
    Some(reference) => {
      guard moonfort_live_output_reference_valid(
        reference,
        receipt,
        plan.grant.limits.output_bytes,
        @clock.epoch.now().ms(),
      ) else {
        fail("MoonFort live output metadata is invalid or mismatched")
      }
    }
    None => ()
  }
  receipt
}

///|
pub async fn persist_sandbox_audit(
  config : SandboxExecutorConfig,
  plan : SandboxApprovalPlan,
  receipt : MoonFortReceipt,
) -> String {
  let path = @pathx.join(config.receipt_root, "\{plan.grant.request_id}.json")
  let temporary = path + ".tmp"
  let audit = SandboxAuditRecord::{ protocol_version: 3, plan, receipt }
  @fsx.write_to_file(temporary, audit.to_json().stringify())
  @fsx.atomic_rename(temporary, path)
  path
}

///|
pub(all) struct SandboxExecution {
  plan : SandboxApprovalPlan
  receipt : MoonFortReceipt
  audit_path : String
} derive(Debug, Eq, ToJson, @json.FromJson)

///|
/// Run only the fixed `moon check` capability through the configured grant
/// publisher and one-shot executor. No host fallback or executable selector is
/// exposed.
pub async fn run_moon_check(
  config : SandboxExecutorConfig,
  workspace : String,
  working_directory : String,
  target : String,
  timeout_ms : Int,
) -> SandboxExecution {
  let plan = make_moon_check_plan(
    config, workspace, working_directory, target, timeout_ms,
  )
  validate_moon_check_plan(plan, config, workspace, working_directory, target)
  let receipt = invoke_moonfort(config, plan)
  let audit_path = persist_sandbox_audit(config, plan, receipt)
  { plan, receipt, audit_path }
}

///|
/// Run only the fixed structured-diagnostics form of `moon check` through
/// MoonFort. The caller cannot add compiler flags, executables, or shell text.
pub async fn run_moon_diagnostics(
  config : SandboxExecutorConfig,
  workspace : String,
  working_directory : String,
  target : String,
  timeout_ms : Int,
) -> SandboxExecution {
  let plan = make_moon_diagnostics_plan(
    config, workspace, working_directory, target, timeout_ms,
  )
  validate_moon_diagnostics_plan(
    plan, config, workspace, working_directory, target,
  )
  let receipt = invoke_moonfort(config, plan)
  let audit_path = persist_sandbox_audit(config, plan, receipt)
  { plan, receipt, audit_path }
}

///|
/// Execute one typed capability through MoonFort. This is appropriate for
/// structured tools such as `moon`; arbitrary shell text must use
/// `run_approved_shell` with a plan persisted before human approval.
pub async fn run_exec(
  config : SandboxExecutorConfig,
  workspace : String,
  working_directory : String,
  tool : String,
  args : Array[String],
  timeout_ms : Int,
) -> SandboxExecution {
  let plan = make_exec_plan(
    config, workspace, working_directory, tool, args, timeout_ms,
  )
  validate_exec_plan(plan, config, workspace, working_directory, tool, args)
  let receipt = invoke_moonfort(config, plan)
  let audit_path = persist_sandbox_audit(config, plan, receipt)
  { plan, receipt, audit_path }
}

///|
/// Consume an exact shell plan that survived the operator approval round-trip.
/// Rebuilding a plan here would allow command/profile substitution between
/// display and execution, so callers pass the persisted plan verbatim.
pub async fn run_approved_shell(
  config : SandboxExecutorConfig,
  workspace : String,
  working_directory : String,
  command : String,
  plan : SandboxApprovalPlan,
) -> SandboxExecution {
  validate_approved_plan(plan, config, workspace, working_directory, command)
  let receipt = invoke_moonfort(config, plan)
  let audit_path = persist_sandbox_audit(config, plan, receipt)
  { plan, receipt, audit_path }
}

///|
/// Consume a persisted typed-exec plan after a human approval round-trip.
pub async fn run_approved_exec(
  config : SandboxExecutorConfig,
  workspace : String,
  working_directory : String,
  tool : String,
  args : Array[String],
  plan : SandboxApprovalPlan,
) -> SandboxExecution {
  validate_exec_plan(plan, config, workspace, working_directory, tool, args)
  let receipt = invoke_moonfort(config, plan)
  let audit_path = persist_sandbox_audit(config, plan, receipt)
  { plan, receipt, audit_path }
}
