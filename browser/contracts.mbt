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
pub(all) enum BrowserPageTrust {
  TrustedLocalPage
  UntrustedExternalPage
  PromptInjectionSuspected
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserDestinationClass {
  DestinationNotApplicable
  PublicInternetDestination
  LoopbackDestination
  PrivateNetworkDestination
  LinkLocalDestination
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserTransferVerdict {
  TransferNotScanned
  TransferClean
  TransferRejected(String)
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
  mutation_authority_id : String
  mutation_authority_nonce : String
  mutation_authority_expires_at : String
  credential_handles : Array[String]
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
  page_trust : BrowserPageTrust
  credential_handle : String
  transfer_path : String
  idempotency_key : String
  fresh_authority_nonce : String
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
  page_trust : BrowserPageTrust
  destination_class : BrowserDestinationClass
  quarantine_ref : String
  idempotency_key : String
  fresh_authority_nonce : String
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
  mutation_authority_id? : String = "",
  mutation_authority_nonce? : String = "",
  mutation_authority_expires_at? : String = "",
  credential_handles? : Array[String] = [],
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
    mutation_authority_id,
    mutation_authority_nonce,
    mutation_authority_expires_at,
    credential_handles,
  }
}

///|
fn loopback_host_with_optional_port(
  host : String,
  loopback_host : String,
) -> Bool {
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
        scope.allowed_origins.length() > 0 &&
        scope.allowed_origins.all(browser_external_origin_allowed) {
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
  page_trust? : BrowserPageTrust = TrustedLocalPage,
  credential_handle? : String = "",
  transfer_path? : String = "",
  idempotency_key? : String = "",
  fresh_authority_nonce? : String = "",
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
    page_trust,
    credential_handle,
    transfer_path,
    idempotency_key,
    fresh_authority_nonce,
    created_at,
  }
}

///|
pub fn browser_effect_mutates_external_state(
  effect : BrowserEffectClass,
) -> Bool {
  effect is UploadFile ||
  effect is DownloadFile ||
  effect is SubmitExternalMutation ||
  effect is RequestPhysicalEffect
}

///|
fn browser_external_host_forbidden(host : String) -> Bool {
  host == "localhost" ||
  host == "0.0.0.0" ||
  host == "[::]" ||
  host == "[::1]" ||
  host.has_suffix(".localhost") ||
  host.has_suffix(".local") ||
  host.has_suffix(".internal") ||
  host == "169.254.169.254" ||
  host.has_prefix("127.") ||
  host.has_prefix("10.") ||
  host.has_prefix("192.168.") ||
  host.has_prefix("172.16.") ||
  host.has_prefix("172.17.") ||
  host.has_prefix("172.18.") ||
  host.has_prefix("172.19.") ||
  host.has_prefix("172.20.") ||
  host.has_prefix("172.21.") ||
  host.has_prefix("172.22.") ||
  host.has_prefix("172.23.") ||
  host.has_prefix("172.24.") ||
  host.has_prefix("172.25.") ||
  host.has_prefix("172.26.") ||
  host.has_prefix("172.27.") ||
  host.has_prefix("172.28.") ||
  host.has_prefix("172.29.") ||
  host.has_prefix("172.30.") ||
  host.has_prefix("172.31.") ||
  host.has_prefix("100.64.") ||
  host.has_prefix("198.18.") ||
  host.has_prefix("198.19.") ||
  host.has_prefix("0.") ||
  host.has_prefix("169.254.") ||
  host.has_prefix("[fc") ||
  host.has_prefix("[fd") ||
  host.has_prefix("[fe8") ||
  host.has_prefix("[fe9") ||
  host.has_prefix("[fea") ||
  host.has_prefix("[feb")
}

///|
fn browser_external_authority_valid(authority : String) -> Bool {
  let parts = authority.split(":").to_array()
  if parts.length() == 1 {
    return true
  }
  if parts.length() != 2 {
    return false
  }
  let port = parts[1]
  if port.length() == 0 {
    return false
  }
  let mut port_number = 0
  for index = 0; index < port.length(); index = index + 1 {
    let codepoint = port[index].to_int()
    if codepoint < 48 || codepoint > 57 {
      return false
    }
    port_number = port_number * 10 + codepoint - 48
    if port_number > 65535 {
      return false
    }
  }
  port_number > 0
}

///|
pub fn browser_origin_from_external_url(url : StringView) -> String? {
  let value = url.to_owned().trim().to_owned().to_lower()
  if !value.has_prefix("https://") {
    return None
  }
  let rest = value["https://".length():].to_owned()
  let authority = rest.split("/").to_array()[0].to_owned()
  if authority == "" ||
    authority.contains("@") ||
    authority.contains("?") ||
    authority.contains("#") ||
    !browser_external_authority_valid(authority) {
    return None
  }
  // IPv6 literals stay denied until the native resolver can classify them
  // without relying on string-only policy.
  if authority.has_prefix("[") {
    return None
  }
  let host = authority.split(":").to_array()[0].to_owned()
  if browser_external_host_forbidden(host) {
    None
  } else {
    Some("https://" + authority)
  }
}

///|
pub fn browser_external_origin_allowed(origin : String) -> Bool {
  match browser_origin_from_external_url(origin) {
    Some(normalized) => normalized == origin.trim().to_owned().to_lower()
    None => false
  }
}

///|
pub fn browser_path_inside_root(path : StringView, root : StringView) -> Bool {
  let value = path.to_owned().trim().to_owned()
  let boundary = root
    .to_owned()
    .trim()
    .to_owned()
    .trim_end(chars="/")
    .to_owned()
  boundary != "" &&
  (value == boundary || value.has_prefix(boundary + "/")) &&
  !value.contains("/../") &&
  !value.has_suffix("/..")
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
    Reload
    | StopLoading
    | Click
    | TypeText
    | PressKey
    | SelectOption
    | SetViewport => InteractLocalPage
    CaptureScreenshot | CaptureDiagnostics => InspectVisiblePage
  }
}
