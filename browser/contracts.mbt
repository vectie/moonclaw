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
  ApprovedExternalOrigin
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserNetworkPolicy {
  LocalAssetsOnly
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
  network_policy? : BrowserNetworkPolicy = LocalAssetsOnly,
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
