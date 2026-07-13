///|
pub(all) enum BrowserHostStatus {
  Completed
  CancelledByHost(String)
  RejectedByHost(String)
  Crashed(String)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct BrowserHostCommand {
  request_id : String
  session_id : String
  action_id : String
  actor : BrowserActor
  actor_id : String
  operation : BrowserOperation
  effect_class : BrowserEffectClass
  origin_class : BrowserOriginClass
  network_policy : BrowserNetworkPolicy
  allowed_origins : Array[String]
  semantic_target : String
  redacted_arguments : String
  expected_observation : String
  expected_before_digest : String
  code_revision : String
  authority_envelope_id : String
  capability_digest : String
  capability_expires_at : String
  page_trust : BrowserPageTrust
  credential_handle : String
  transfer_path : String
  upload_sources : Array[String]
  download_quarantine_root : String
  idempotency_key : String
  mutation_authority_id : String
  fresh_authority_nonce : String
  mutation_authority_expires_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub struct BrowserHostResult {
  host_receipt_id : String
  request_id : String
  session_id : String
  action_id : String
  code_revision : String
  authority_envelope_id : String
  capability_digest : String
  page_trust : BrowserPageTrust
  destination_class : BrowserDestinationClass
  quarantine_ref : String
  transfer_verdict : BrowserTransferVerdict
  idempotency_key : String
  fresh_authority_valid : Bool
  status : BrowserHostStatus
  before_state_digest : String
  after_state_digest : String
  screenshot_before_ref : String
  screenshot_after_ref : String
  observations : Array[String]
  target_resolved : Bool
  completed_at : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum BrowserDispatch {
  Ready(BrowserHostCommand)
  Rejected(BrowserActionReceipt)
  Duplicate(BrowserActionReceipt)
} derive(Debug, Eq, ToJson)

///|
pub fn browser_host_result(
  host_receipt_id~ : String,
  request_id~ : String,
  session_id~ : String,
  action_id~ : String,
  code_revision~ : String,
  authority_envelope_id~ : String,
  capability_digest~ : String,
  page_trust? : BrowserPageTrust = TrustedLocalPage,
  destination_class? : BrowserDestinationClass = DestinationNotApplicable,
  quarantine_ref? : String = "",
  transfer_verdict? : BrowserTransferVerdict = TransferNotScanned,
  idempotency_key? : String = "",
  fresh_authority_valid? : Bool = false,
  status~ : BrowserHostStatus,
  before_state_digest~ : String,
  after_state_digest~ : String,
  screenshot_before_ref? : String = "",
  screenshot_after_ref? : String = "",
  observations? : Array[String] = [],
  target_resolved? : Bool = true,
  completed_at? : String = "",
) -> BrowserHostResult {
  {
    host_receipt_id,
    request_id,
    session_id,
    action_id,
    code_revision,
    authority_envelope_id,
    capability_digest,
    page_trust,
    destination_class,
    quarantine_ref,
    transfer_verdict,
    idempotency_key,
    fresh_authority_valid,
    status,
    before_state_digest,
    after_state_digest,
    screenshot_before_ref,
    screenshot_after_ref,
    observations,
    target_resolved,
    completed_at,
  }
}
