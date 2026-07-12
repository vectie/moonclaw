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
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct BrowserSessionScope {
  session_id : String
  workspace_id : String
  book_revision : String
  code_revision : String
  run_id : String
  authority_envelope_id : String
  allowed_origins : Array[String]
  permitted_effects : Array[BrowserEffectClass]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct BrowserAction {
  action_id : String
  session_id : String
  actor : BrowserActor
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
  operation : BrowserOperation
  outcome : BrowserActionOutcome
  observations : Array[String]
  authority_envelope_id : String
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
  allowed_origins? : Array[String] = [],
  permitted_effects? : Array[BrowserEffectClass] = [
    RenderLocalArtifact,
    InspectVisiblePage,
    InteractLocalPage,
    SaveWorkspaceEvidence,
  ],
) -> BrowserSessionScope {
  {
    session_id,
    workspace_id,
    book_revision,
    code_revision,
    run_id,
    authority_envelope_id,
    allowed_origins,
    permitted_effects,
  }
}

///|
pub fn browser_action(
  action_id~ : String,
  session_id~ : String,
  actor~ : BrowserActor,
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
