///|
priv struct MoonDeskPromotionCheckpoint {
  request : MoonDeskPromotionRequest
  response : MoonFortPromotionResponse
} derive(ToJson, @json.FromJson)

///|
fn moondesk_promotion_checkpoint_path(
  root : String,
  request : MoonDeskPromotionRequest,
) -> String {
  let identity : Json = {
    "instance": request.instance_id,
    "workspace": request.workspace_id,
    "retention": request.retention_id,
  }
  let key = @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(identity.stringify())),
  )
  @pathx.join(root, "promotion-\{key}.json")
}

///|
fn moondesk_promotion_same_selection(
  left : MoonDeskPromotionRequest,
  right : MoonDeskPromotionRequest,
) -> Bool {
  left.protocol_version == right.protocol_version &&
  left.instance_id == right.instance_id &&
  left.workspace_id == right.workspace_id &&
  left.retention_id == right.retention_id &&
  left.approval_digest == right.approval_digest &&
  left.command_digest == right.command_digest &&
  left.items == right.items
}

///|
async fn moondesk_promotion_load_checkpoint(
  path : String,
) -> MoonDeskPromotionCheckpoint? {
  if !@fs.exists(path) {
    return None
  }
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  guard file.kind() is Regular && file.size() <= 131_072L else {
    fail("Return receipt is unavailable")
  }
  let bytes = @buffer.Buffer(size_hint=2_048)
  for ;; {
    guard file.read_some(max_len=(131_073 - bytes.length()).min(4_096))
      is Some(chunk) else {
      break
    }
    guard bytes.length() + chunk.length() <= 131_072 else {
      fail("Return receipt is unavailable")
    }
    bytes.write_bytes(chunk)
  }
  let value = @json.parse(@encoding/utf8.decode(bytes.to_bytes()))
  if value is { "pending_attempt": true, .. } {
    fail("Return attempt has no confirmed receipt; inspect the destination")
  }
  Some(@json.from_json(value))
}

///|
async fn moondesk_promotion_save_checkpoint(
  path : String,
  receipt_root : String,
  value : Json,
  temporary_suffix : String,
) -> Unit {
  @fs.write_file(
    path + temporary_suffix,
    value.stringify(),
    create_mode=CreateOrTruncate,
    permission=0o600,
    sync=Full,
  )
  @fs.rename(path + temporary_suffix, path, replace=true)
  let directory = @fs.open(receipt_root, mode=ReadOnly)
  defer directory.close()
  directory.sync()
}

///|
// This stores only the exact reviewed mapping and validated Fort result. It
// never publishes a grant, starts execution, or reads a destination as proof.
async fn moondesk_promotion_with_receipt(
  request : MoonDeskPromotionRequest,
  receipt_root : String,
  invoke : async () -> MoonFortPromotionResponse,
) -> Json {
  let path = moondesk_promotion_checkpoint_path(receipt_root, request)
  let lock = @fs.open(
    path + ".lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
    permission=0o600,
  )
  defer lock.close()
  lock.lock(Exclusive)
  defer lock.unlock()
  if moondesk_promotion_load_checkpoint(path) is Some(saved) {
    let previous = moondesk_promotion_validate_response(
      saved.request,
      saved.response,
    )
    if previous.destination_outcome != "not-applied" ||
      previous.error is Some({ code: "promotion-recovery-required", .. }) {
      guard moondesk_promotion_same_selection(saved.request, request) else {
        fail("Saved return receipt belongs to a different reviewed selection")
      }
      return moondesk_promotion_public_response(request, previous)
    }
  }
  // Durably supersede any earlier safe refusal before this attempt can mutate
  // the destination. If invocation or final persistence fails, readback and
  // repeated requests must remain unresolved instead of reviving that refusal.
  let pending : Json = { "request": request.to_json(), "pending_attempt": true }
  moondesk_promotion_save_checkpoint(path, receipt_root, pending, ".starting")
  let response = moondesk_promotion_validate_response(request, invoke())
  let checkpoint = MoonDeskPromotionCheckpoint::{ request, response, }
  moondesk_promotion_save_checkpoint(
    path,
    receipt_root,
    checkpoint.to_json(),
    ".pending",
  )
  moondesk_promotion_public_response(request, response)
}

///|
async fn moondesk_promotion_read_receipt(
  request : MoonDeskPromotionRequest,
  receipt_root : String,
) -> Json {
  guard moondesk_promotion_load_checkpoint(
      moondesk_promotion_checkpoint_path(receipt_root, request),
    )
    is Some(saved) &&
    moondesk_promotion_same_selection(saved.request, request) else {
    fail("No matching saved return receipt")
  }
  moondesk_promotion_public_response(
    request,
    moondesk_promotion_validate_response(request, saved.response),
  )
}

///|
async fn read_moondesk_promotion_receipt(
  request : MoonDeskPromotionRequest,
  route_config : @moondesk_sandbox_config.Config,
) -> Json {
  guard request.instance_id == route_config.instance_id &&
    request.workspace_id == route_config.workspace_id else {
    fail("Return receipt does not match the configured instance")
  }
  guard @moonfort_config.load_promotion_adapter_config() is Some(launcher) else {
    fail("Return receipt storage is unavailable")
  }
  moondesk_promotion_read_receipt(request, launcher.receipt_root)
}
