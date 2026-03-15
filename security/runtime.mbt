///|
pub struct CommandPolicy {
  native : String
  native_skills : String
  restart : Bool
  owner_display : String
} derive(ToJson, FromJson, Show)

///|
pub struct PairingRecord {
  key : String
  channel_id : String
  account_id : String
  recipient : String
  status : String
  created_at : Int
  approved_at : Int?
} derive(ToJson, FromJson, Show)

///|
pub struct ApprovalRecord {
  token : String
  action_kind : String
  action_target : String
  scope_key : String
  status : String
  created_at : Int
  approved_at : Int?
} derive(ToJson, FromJson, Show)

///|
struct PersistedSecurityState {
  pairings : Array[PairingRecord]
  approvals : Array[ApprovalRecord]
} derive(ToJson, FromJson, Show)

///|
pub enum SecurityChatAction {
  Pair
  PairStatus
  RevokePair
  Approve(String)
  Approvals
}

///|
pub struct SecurityRuntime {
  home : String
  cwd : String
  mut session_dm_scope : String
  mut command_policy : CommandPolicy
  pairings : Map[String, PairingRecord]
  approvals : Map[String, ApprovalRecord]
}

///|
fn config_path_candidates(home : String, cwd : String) -> Array[String] {
  [
    home |> @pathx.join("moonclaw.json"),
    home |> @pathx.join(".moonclaw") |> @pathx.join("moonclaw.json"),
    cwd |> @pathx.join("moonclaw.json"),
    cwd |> @pathx.join(".moonclaw") |> @pathx.join("moonclaw.json"),
  ]
}

///|
fn persisted_state_path(home : String) -> String {
  home |> @pathx.join("security") |> @pathx.join("state.json")
}

///|
fn default_command_policy() -> CommandPolicy {
  CommandPolicy::{
    native: "auto",
    native_skills: "auto",
    restart: true,
    owner_display: "raw",
  }
}

///|
fn pairing_key(
  channel_id : String,
  account_id : String,
  recipient : String,
) -> String {
  "\{channel_id}:\{account_id}:\{recipient}"
}

///|
pub fn approval_scope_key(
  channel_id : String,
  account_id : String,
  recipient : String,
  thread_id : String?,
) -> String {
  let thread = thread_id.unwrap_or("")
  if thread.is_blank() {
    "\{channel_id}:\{account_id}:\{recipient}"
  } else {
    "\{channel_id}:\{account_id}:\{recipient}:\{thread}"
  }
}

///|
async fn load_security_config(home : String, cwd : String) -> Json? {
  let mut loaded : Json? = None
  for path in config_path_candidates(home, cwd) {
    let exists = @fsx.exists(path) catch { _ => false }
    if !exists {
      continue
    }
    let text = @fsx.read_file(path) catch { _ => continue }
    let json = @json.parse(text) catch { _ => continue }
    loaded = Some(json)
  }
  loaded
}

///|
fn json_string_at(value : Json, field : String) -> String? {
  match value {
    Object(obj) =>
      match obj.get(field) {
        Some(String(text)) if !text.trim().is_empty() =>
          Some(text.trim().to_string())
        _ => None
      }
    _ => None
  }
}

///|
fn json_bool_at(value : Json, field : String) -> Bool? {
  match value {
    Object(obj) =>
      match obj.get(field) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
fn configured_session_dm_scope(json : Json?) -> String {
  match json {
    Some(Object(root)) =>
      match root.get("session") {
        Some(session) =>
          json_string_at(session, "dmScope").unwrap_or(
            "per-account-channel-peer",
          )
        None => "per-account-channel-peer"
      }
    _ => "per-account-channel-peer"
  }
}

///|
fn configured_command_policy(json : Json?) -> CommandPolicy {
  match json {
    Some(Object(root)) =>
      match root.get("commands") {
        Some(commands) =>
          CommandPolicy::{
            native: json_string_at(commands, "native").unwrap_or("auto"),
            native_skills: json_string_at(commands, "nativeSkills").unwrap_or(
              "auto",
            ),
            restart: json_bool_at(commands, "restart").unwrap_or(true),
            owner_display: json_string_at(commands, "ownerDisplay").unwrap_or(
              "raw",
            ),
          }
        None => default_command_policy()
      }
    _ => default_command_policy()
  }
}

///|
pub async fn SecurityRuntime::new(
  home~ : String,
  cwd~ : String,
) -> SecurityRuntime {
  let runtime = SecurityRuntime::{
    home,
    cwd,
    session_dm_scope: "per-account-channel-peer",
    command_policy: default_command_policy(),
    pairings: {},
    approvals: {},
  }
  runtime.load()
  runtime
}

///|
pub async fn SecurityRuntime::load(self : SecurityRuntime) -> Unit {
  let config = load_security_config(self.home, self.cwd)
  self.session_dm_scope = configured_session_dm_scope(config)
  self.command_policy = configured_command_policy(config)

  self.pairings.clear()
  self.approvals.clear()
  let path = persisted_state_path(self.home)
  let exists = @fsx.exists(path) catch { _ => false }
  if !exists {
    return
  }
  let text = @fsx.read_file(path) catch { _ => return }
  let json = @json.parse(text) catch { _ => return }
  let state : PersistedSecurityState = @json.from_json(json) catch {
    _ => return
  }
  for pairing in state.pairings {
    self.pairings[pairing.key] = pairing
  }
  for approval in state.approvals {
    self.approvals[approval.token] = approval
  }
}

///|
pub async fn SecurityRuntime::save(self : SecurityRuntime) -> Unit {
  let path = persisted_state_path(self.home)
  let dir = self.home |> @pathx.join("security")
  @fsx.make_directory(dir, recursive=true) catch {
    _ => ()
  }
  let state = PersistedSecurityState::{
    pairings: self.pairings.values().to_array(),
    approvals: self.approvals.values().to_array(),
  }
  @fsx.write_to_file(path, state.to_json().stringify()) catch {
    _ => ()
  }
}

///|
pub fn SecurityRuntime::session_dm_scope(self : SecurityRuntime) -> String {
  self.session_dm_scope
}

///|
pub fn SecurityRuntime::command_policy(self : SecurityRuntime) -> CommandPolicy {
  self.command_policy
}

///|
pub fn SecurityRuntime::allows_native_commands(
  self : SecurityRuntime,
  supports_native : Bool,
) -> Bool {
  match self.command_policy.native {
    "off" | "disabled" | "false" => false
    "on" | "enabled" | "true" => true
    _ => supports_native
  }
}

///|
pub fn SecurityRuntime::allows_skill_commands(self : SecurityRuntime) -> Bool {
  match self.command_policy.native_skills {
    "off" | "disabled" | "false" => false
    _ => true
  }
}

///|
pub fn SecurityRuntime::is_paired(
  self : SecurityRuntime,
  channel_id : String,
  account_id : String,
  recipient : String,
) -> Bool {
  match self.pairings.get(pairing_key(channel_id, account_id, recipient)) {
    Some(record) => record.status == "approved"
    None => false
  }
}

///|
pub async fn SecurityRuntime::approve_pairing(
  self : SecurityRuntime,
  channel_id : String,
  account_id : String,
  recipient : String,
  now_ms : Int,
) -> PairingRecord {
  let key = pairing_key(channel_id, account_id, recipient)
  let record = PairingRecord::{
    key,
    channel_id,
    account_id,
    recipient,
    status: "approved",
    created_at: match self.pairings.get(key) {
      Some(existing) => existing.created_at
      None => now_ms
    },
    approved_at: Some(now_ms),
  }
  self.pairings[key] = record
  self.save()
  record
}

///|
pub async fn SecurityRuntime::revoke_pairing(
  self : SecurityRuntime,
  channel_id : String,
  account_id : String,
  recipient : String,
) -> Bool {
  let key = pairing_key(channel_id, account_id, recipient)
  let existed = self.pairings.contains(key)
  self.pairings.remove(key)
  self.save()
  existed
}

///|
pub fn SecurityRuntime::pairing_status_text(
  self : SecurityRuntime,
  channel_id : String,
  account_id : String,
  recipient : String,
) -> String {
  if self.is_paired(channel_id, account_id, recipient) {
    "Pairing status: approved for \{channel_id}/\{account_id}/\{recipient}"
  } else {
    "Pairing status: not approved for \{channel_id}/\{account_id}/\{recipient}"
  }
}

///|
pub async fn SecurityRuntime::request_approval(
  self : SecurityRuntime,
  token : String,
  action_kind : String,
  action_target : String,
  scope_key : String,
  now_ms : Int,
) -> ApprovalRecord {
  let record = ApprovalRecord::{
    token,
    action_kind,
    action_target,
    scope_key,
    status: "pending",
    created_at: now_ms,
    approved_at: None,
  }
  self.approvals[token] = record
  self.save()
  record
}

///|
pub async fn SecurityRuntime::approve_token(
  self : SecurityRuntime,
  token : String,
  now_ms : Int,
) -> ApprovalRecord? {
  match self.approvals.get(token) {
    Some(record) => {
      let approved = ApprovalRecord::{
        ..record,
        status: "approved",
        approved_at: Some(now_ms),
      }
      self.approvals[token] = approved
      self.save()
      Some(approved)
    }
    None => None
  }
}

///|
pub fn SecurityRuntime::list_pending_approvals(
  self : SecurityRuntime,
  scope_key : String,
) -> Array[ApprovalRecord] {
  self.approvals
  .values()
  .to_array()
  .filter(fn(record) {
    record.scope_key == scope_key && record.status == "pending"
  })
}

///|
pub fn SecurityRuntime::matching_pending_approval(
  self : SecurityRuntime,
  action_kind : String,
  action_target : String,
  scope_key : String,
) -> ApprovalRecord? {
  for _, record in self.approvals {
    if record.scope_key == scope_key &&
      record.action_kind == action_kind &&
      record.action_target == action_target &&
      record.status == "pending" {
      return Some(record)
    }
  }
  None
}

///|
pub async fn SecurityRuntime::consume_approval(
  self : SecurityRuntime,
  action_kind : String,
  action_target : String,
  scope_key : String,
) -> Bool {
  let mut matched : String? = None
  for token, record in self.approvals {
    if record.scope_key == scope_key &&
      record.action_kind == action_kind &&
      record.action_target == action_target &&
      record.status == "approved" {
      matched = Some(token)
      break
    }
  }
  match matched {
    Some(token) => {
      self.approvals.remove(token)
      self.save()
      true
    }
    None => false
  }
}

///|
pub fn parse_security_chat_action(text : String) -> SecurityChatAction? {
  let trimmed = text.trim().to_string()
  guard trimmed.has_prefix("/") else { return None }
  let parts = trimmed.split(" ").collect()
  let command = parts.get(0).unwrap_or("")
  let arg = if parts.length() > 1 {
    parts[1:].join(" ").trim().to_string()
  } else {
    ""
  }
  match command {
    "/pair" => Some(SecurityChatAction::Pair)
    "/pair-status" => Some(SecurityChatAction::PairStatus)
    "/revoke-pair" => Some(SecurityChatAction::RevokePair)
    "/approve" if !arg.is_blank() => Some(SecurityChatAction::Approve(arg))
    "/approvals" => Some(SecurityChatAction::Approvals)
    _ => None
  }
}

///|
pub fn render_pairing_required(dm_policy : String) -> String {
  "This conversation requires pairing under dmPolicy=\{dm_policy}. Use `/pair` to approve this chat before sending normal messages."
}

///|
pub fn render_native_commands_disabled() -> String {
  "Native commands are disabled by command policy for this channel."
}

///|
pub fn render_pending_approval(record : ApprovalRecord) -> String {
  [
    "Approval required for \{record.action_kind} \{record.action_target}.",
    "Token: `\{record.token}`",
    "Approve with `/approve \{record.token}` and rerun the command.",
  ].join("\n")
}

///|
pub fn render_approval_confirmed(record : ApprovalRecord) -> String {
  "Approved token `\{record.token}` for \{record.action_kind} \{record.action_target}."
}

///|
pub fn render_approval_not_found(token : String) -> String {
  "Approval token not found: `\{token}`"
}

///|
pub fn render_approvals(records : Array[ApprovalRecord]) -> String {
  if records.is_empty() {
    "No pending approvals."
  } else {
    let items = records.map(fn(record) {
      "- `\{record.token}` \{record.action_kind} \{record.action_target}"
    })
    ["Pending approvals:", ..items].join("\n")
  }
}
