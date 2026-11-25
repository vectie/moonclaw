///|
/// Auth status for a single provider
#derive(ToJson)
priv struct ProviderAuthStatus {
  authenticated : Bool
  email : String?
  plan : String?
}

///|
/// Combined auth status for all providers
#derive(ToJson)
priv struct AllAuthStatus {
  codex : ProviderAuthStatus
  copilot : ProviderAuthStatus
}

///|
/// Response for starting Codex OAuth flow
#derive(ToJson)
priv struct StartCodexAuthResponse {
  auth_url : String
  state : String
}

///|
/// Response for starting Copilot OAuth flow
#derive(ToJson)
priv struct StartCopilotAuthResponse {
  user_code : String
  verification_uri : String
  expires_in : Int32
  interval : Int32
}

///|
/// GET /v1/auth/status - Returns auth status for all providers
async fn Daemon::get_auth_status(
  self : Daemon,
  w : @httpx.ResponseWriter,
) -> Unit {
  let codex_status = self.get_codex_auth_status()
  let copilot_status = self.get_copilot_auth_status()
  let status : AllAuthStatus = { codex: codex_status, copilot: copilot_status, }
  w.header().set("Content-Type", "application/json")
  w.write_header(200)
  w.write(@json.to_json(status).stringify())
}

///|
/// Get Codex auth status by checking credentials and extracting user info
async fn Daemon::get_codex_auth_status(self : Daemon) -> ProviderAuthStatus {
  if !@codex.credentials_exist_for_workspace_root(root=self.home) {
    return { authenticated: false, email: None, plan: None, }
  }
  try {
    let credentials = @codex.load_credentials_for_workspace_root(root=self.home)
    let claims = @codex.extract_token_claims(credentials.idToken)
    {
      authenticated: true,
      email: Some(claims.email),
      plan: Some(claims.chatgptPlanType),
    }
  } catch {
    _ => { authenticated: false, email: None, plan: None, }
  }
}

///|
/// Get Copilot auth status by checking credentials
async fn Daemon::get_copilot_auth_status(self : Daemon) -> ProviderAuthStatus {
  if !@copilot.credentials_exist_for_workspace_root(root=self.home) {
    return { authenticated: false, email: None, plan: None, }
  }
  // Copilot doesn't provide email/plan info in the token
  { authenticated: true, email: None, plan: None, }
}
