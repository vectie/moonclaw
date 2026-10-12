///|
fn moondesk_promotion_identity_path(
  root : String,
  instance : String,
  workspace : String,
  retention : String,
) -> String {
  let identity : Json = {
    "instance": instance,
    "workspace": workspace,
    "retention": retention,
  }
  let key = @crypto.bytes_to_hex_string(
    @crypto.sha256(@encoding/utf8.encode(identity.stringify())),
  )
  @pathx.join(root, "promotion-\{key}.json")
}
