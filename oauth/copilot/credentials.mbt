///|
pub(all) struct Credentials {
  github_token : String
  copilot_token : String
  copilot_token_expires_at : Int64
} derive(Debug, ToJson, FromJson)

///|
fn get_home() -> String {
  @os.home() catch {
    err => {
      println("ERROR in @os.home(): \{err}")
      abort("Failed to get home directory")
    }
  }
}

///|
fn get_credentials_path_for_workspace_root(root : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(
    root,
    "moonclaw",
    CREDENTIALS_FILE,
  )
}

///|
pub async fn save_credentials(credentials : Credentials) -> Unit {
  save_credentials_for_workspace_root(credentials, root=get_home())
}

///|
pub async fn save_credentials_for_workspace_root(
  credentials : Credentials,
  root~ : String,
) -> Unit {
  let path = get_credentials_path_for_workspace_root(root)
  let dir = @pathx.dirname(path)
  @fsx.make_directory(dir, recursive=true, exists_ok=true)
  @fsx.write_to_file(path, credentials.to_json().stringify(), create=0o600)
}

///|
pub async fn load_credentials() -> Credentials raise Error {
  load_credentials_for_workspace_root(root=get_home())
}

///|
pub async fn load_credentials_for_workspace_root(
  root~ : String,
) -> Credentials raise Error {
  let path = get_credentials_path_for_workspace_root(root)
  if !@fsx.exists_as_file(path) {
    raise ParseError("Copilot credentials file not found")
  }
  let content = @fsx.read_file(path)
  @json.from_json(@json.parse(content))
}

///|
pub fn Credentials::is_token_valid(self : Credentials, now : Int64) -> Bool {
  self.copilot_token_expires_at - 60L > now
}

///|
/// Returns true if credentials file exists
pub async fn credentials_exist() -> Bool {
  credentials_exist_for_workspace_root(root=get_home())
}

///|
pub async fn credentials_exist_for_workspace_root(root~ : String) -> Bool {
  let path = get_credentials_path_for_workspace_root(root)
  @fsx.exists_as_file(path)
}

///|
/// Deletes the credentials file if it exists
pub async fn delete_credentials() -> Unit {
  delete_credentials_for_workspace_root(root=get_home())
}

///|
pub async fn delete_credentials_for_workspace_root(root~ : String) -> Unit {
  let path = get_credentials_path_for_workspace_root(root)
  if @fsx.exists_as_file(path) {
    @fsx.remove(path)
  }
}
