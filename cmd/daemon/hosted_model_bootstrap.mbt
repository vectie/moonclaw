///|
/// Hosted MoonDesk uses a separate MoonGate process inside each subject's pod.
/// The only upstream visible to that process is the pod-local LunaNexa model
/// proxy, which rechecks the user's lease and injects the scoped API credential.
fn hosted_model_alias() -> String? {
  guard (@os.getenv("MOONCLAW_HOSTED_MODEL_ALIAS") catch { _ => None })
    is Some(raw) else {
    return None
  }
  let model = raw.trim().to_owned()
  if lunanexa_identifier(model, 128) {
    Some(model)
  } else {
    None
  }
}

///|
async fn Daemon::bootstrap_hosted_model(_self : Daemon) -> Unit {
  guard hosted_model_alias() is Some(model) else { return }
  while true {
    let client = @moongate.discover()
    match
      client.configure_workspace_provider(
        "http://127.0.0.1:8189/v1", "managed-loopback-proxy", model,
      ) {
      Ok(_) => return
      Err(_) => @async.sleep(1000)
    }
  }
}

///|
test "hosted model alias accepts one bounded model identifier" {
  @os.setenv("MOONCLAW_HOSTED_MODEL_ALIAS", "glm-5.3.flash")
  assert_eq(hosted_model_alias(), Some("glm-5.3.flash"))
  @os.setenv("MOONCLAW_HOSTED_MODEL_ALIAS", "../../other-user")
  assert_eq(hosted_model_alias(), None)
  @os.unsetenv("MOONCLAW_HOSTED_MODEL_ALIAS")
}
