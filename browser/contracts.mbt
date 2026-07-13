///|
pub(all) enum BrowserActor {
  User
  Agent
  Replay
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserOperation {
  Navigate
  Reload
  StopLoading
  Click
  TypeText
  PressKey
  SelectOption
  SetViewport
  CaptureScreenshot
  CaptureDiagnostics
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserEffectClass {
  RenderLocalArtifact
  InspectVisiblePage
  InteractLocalPage
  SaveWorkspaceEvidence
  NavigateExternalOrigin
  UploadFile
  DownloadFile
  SubmitExternalMutation
  RequestPhysicalEffect
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserOriginClass {
  OpaqueLocalPreview
  IsolatedLoopback
  ExternalOrigin
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserNetworkPolicy {
  Offline
  ApprovedOriginsOnly
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserStorageLifetime {
  Ephemeral
  RunScoped
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserSessionStatus {
  Ready
  AgentOperating
  Paused
  UserControl
  Stopped
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserActionOutcome {
  Accepted
  NoOp
  Blocked(String)
  Diverged(String)
  Cancelled(String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct BrowserSessionScope {
  session_id : String
  workspace_id : String
  book_revision : String
  code_revision : String
  run_id : String
  authority_envelope_id : String
  origin_class : BrowserOriginClass
  network_policy : BrowserNetworkPolicy
  storage_lifetime : BrowserStorageLifetime
  allowed_origins : Array[String]
  permitted_effects : Array[BrowserEffectClass]
  download_root : String
  upload_sources : Array[String]
  capability_digest : String
  capability_expires_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct BrowserAction {
  action_id : String
  session_id : String
  actor : BrowserActor
  actor_id : String
  operation : BrowserOperation
  target : String
  value_redacted : String
  expected_observation : String
  code_revision : String
  authority_envelope_id : String
  required_effect : BrowserEffectClass
  created_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct BrowserActionReceipt {
  action_id : String
  session_id : String
  actor : BrowserActor
  actor_id : String
  operation : BrowserOperation
  semantic_target : String
  redacted_arguments : String
  expected_observation : String
  outcome : BrowserActionOutcome
  observations : Array[String]
  before_state_digest : String
  after_state_digest : String
  evidence_refs : Array[String]
  host_receipt_id : String
  authority_envelope_id : String
  capability_digest : String
  capability_expires_at : String
  code_revision : String
  completed_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn browser_session_scope(
  session_id~ : String,
  workspace_id~ : String,
  book_revision~ : String,
  code_revision~ : String,
  run_id~ : String,
  authority_envelope_id~ : String,
  origin_class? : BrowserOriginClass = OpaqueLocalPreview,
  network_policy? : BrowserNetworkPolicy = Offline,
  storage_lifetime? : BrowserStorageLifetime = Ephemeral,
  allowed_origins? : Array[String] = [],
  permitted_effects? : Array[BrowserEffectClass] = [
    RenderLocalArtifact,
    InspectVisiblePage,
    InteractLocalPage,
  ],
  download_root? : String = "",
  upload_sources? : Array[String] = [],
  capability_digest? : String = "local-preview-capability-digest",
  capability_expires_at? : String = "",
) -> BrowserSessionScope {
  {
    session_id,
    workspace_id,
    book_revision,
    code_revision,
    run_id,
    authority_envelope_id,
    origin_class,
    network_policy,
    storage_lifetime,
    allowed_origins,
    permitted_effects,
    download_root,
    upload_sources,
    capability_digest,
    capability_expires_at,
  }
}

///|
fn loopback_host_with_optional_port(host : String, loopback_host : String) -> Bool {
  if host == loopback_host {
    return true
  }
  let prefix = loopback_host + ":"
  if !host.has_prefix(prefix) {
    return false
  }
  let port = host[prefix.length():]
  if port.length() == 0 {
    return false
  }
  for index = 0; index < port.length(); index = index + 1 {
    let codepoint = port[index].to_int()
    if codepoint < 48 || codepoint > 57 {
      return false
    }
  }
  true
}

///|
pub fn browser_loopback_origin_allowed(origin : StringView) -> Bool {
  let value = origin.to_owned().trim().to_owned().to_lower()
  let without_scheme = if value.has_prefix("http://") {
    value["http://".length():].to_owned()
  } else if value.has_prefix("https://") {
    value["https://".length():].to_owned()
  } else {
    return false
  }
  if without_scheme.contains("/") ||
    without_scheme.contains("@") ||
    without_scheme.contains("?") ||
    without_scheme.contains("#") {
    return false
  }
  loopback_host_with_optional_port(without_scheme, "localhost") ||
  loopback_host_with_optional_port(without_scheme, "127.0.0.1") ||
  loopback_host_with_optional_port(without_scheme, "[::1]")
}

///|
pub fn browser_scope_policy_issue(scope : BrowserSessionScope) -> String? {
  match scope.origin_class {
    OpaqueLocalPreview =>
      if scope.allowed_origins.length() == 0 && scope.network_policy is Offline {
        None
      } else {
        Some("opaque-origin-must-have-no-origins-and-offline-policy")
      }
    IsolatedLoopback =>
      if !(scope.network_policy is Offline) {
        Some("isolated-loopback-must-remain-offline")
      } else if scope.allowed_origins.length() != 1 ||
        !browser_loopback_origin_allowed(scope.allowed_origins[0]) {
        Some("isolated-loopback-requires-one-explicit-loopback-origin")
      } else {
        None
      }
    ExternalOrigin =>
      if scope.network_policy is ApprovedOriginsOnly &&
        scope.allowed_origins.length() > 0 {
        None
      } else {
        Some("external-origin-requires-approved-origin-policy")
      }
  }
}

///|
pub fn browser_action(
  action_id~ : String,
  session_id~ : String,
  actor~ : BrowserActor,
  actor_id? : String = "",
  operation~ : BrowserOperation,
  target~ : String,
  value_redacted? : String = "",
  expected_observation? : String = "",
  code_revision~ : String,
  authority_envelope_id~ : String,
  required_effect? : BrowserEffectClass = InteractLocalPage,
  created_at? : String = "",
) -> BrowserAction {
  {
    action_id,
    session_id,
    actor,
    actor_id,
    operation,
    target,
    value_redacted,
    expected_observation,
    code_revision,
    authority_envelope_id,
    required_effect,
    created_at,
  }
}

///|
pub fn BrowserActionReceipt::accepted(self : BrowserActionReceipt) -> Bool {
  self.outcome is Accepted
}

///|
pub fn browser_operation_effect_class(
  operation : BrowserOperation,
) -> BrowserEffectClass {
  match operation {
    Navigate => NavigateExternalOrigin
    Reload | StopLoading | Click | TypeText | PressKey | SelectOption
    | SetViewport => InteractLocalPage
    CaptureScreenshot | CaptureDiagnostics => InspectVisiblePage
  }
}
