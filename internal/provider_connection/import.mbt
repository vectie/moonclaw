///|
/// A connection descriptor failure, an unavailable local service, or a bounded
/// configuration-stage failure. No upstream body or credential is retained.
pub(all) enum ImportError {
  InvalidDescriptor
  GateUnavailable
  Failed(String)
}

///|
priv struct Candidate {
  version : String
  api : String
  base_url : String
  api_key : String
  model : String
  max_output_tokens : Int32
} derive(@json.FromJson)

///|
priv struct GateControl {
  origin : String
  prefix : String
  token : String
}

///|
fn url_parts(value : String) -> (String, String)? {
  if value.length() > 2048 ||
    value.trim() != value ||
    value.contains_char('@') ||
    value.contains_char('?') ||
    value.contains_char('#') ||
    value.contains_char('\\') ||
    value.any(c => c <= ' ' || c > '\u{7f}') {
    return None
  }
  let scheme = if value.has_prefix("https://") {
    "https://"
  } else if value.has_prefix("http://") {
    "http://"
  } else {
    return None
  }
  let rest = value[scheme.length():]
  let boundary = rest.find("/").unwrap_or(rest.length())
  let authority = rest[:boundary].to_owned()
  if authority.is_empty() ||
    !authority.all(c => {
      c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '.' | '-' | ':' | '[' | ']')
    }) {
    return None
  }
  let loopback = ["localhost", "127.0.0.1", "[::1]"].any(host => {
    authority == host ||
    (
      authority.has_prefix(host + ":") &&
      authority[host.length() + 1:].all(c => c.is_ascii_digit()) &&
      authority.length() > host.length() + 1
    )
  })
  if scheme == "http://" && !loopback {
    return None
  }
  Some((scheme + authority, rest[boundary:].trim_end(chars="/").to_owned()))
}

///|
fn candidate_from_json(value : Json) -> Candidate? {
  let candidate : Candidate = @json.from_json(value) catch { _ => return None }
  if candidate.version != "openai.connection.v1" ||
    candidate.api != "chat.completions" ||
    url_parts(candidate.base_url) is None ||
    candidate.base_url.has_suffix("/chat/completions") ||
    candidate.model.is_empty() ||
    candidate.model.length() > 256 ||
    !candidate.model.all(c => c > ' ' && c <= '~') ||
    candidate.api_key.is_empty() ||
    candidate.api_key.length() > 512 ||
    !candidate.api_key.all(c => c > ' ' && c <= '~') ||
    candidate.api_key.has_prefix("api-key-") ||
    candidate.model.contains(candidate.api_key) ||
    candidate.max_output_tokens < 1 ||
    candidate.max_output_tokens > 131072 {
    None
  } else {
    Some(candidate)
  }
}

///|
fn provider_id(candidate : Candidate) -> String {
  let hash = @crypto.bytes_to_hex_string(
    @crypto.sha256(
      @utf8.encode(candidate.base_url + "\n" + candidate.model).to_fixedarray(),
    ),
  )
  "imported-openai-" + hash[:16].to_owned()
}

///|
fn provider_exists(value : Json, id : String) -> Bool {
  match value {
    Array(values) => values.any(value => provider_exists(value, id))
    Object(fields) =>
      fields.get("id") == Some(Json(id)) ||
      fields.values().any(value => provider_exists(value, id))
    _ => false
  }
}

///|
/// This transport addresses only the discovered MoonGate service, never the
/// candidate provider. Redirects and non-2xx responses are rejected, and error
/// bodies are discarded. The caller bounds the entire import to 30 seconds.
async fn gate_request(
  origin : String,
  prefix : String,
  token : String,
  path : String,
  payload : Json?,
  bootstrap~ : Bool = false,
) -> Json {
  let headers : Map[String, String] = {
    "Accept": "application/json",
    "Content-Type": "application/json",
  }
  if bootstrap {
    headers["Origin"] = origin
    headers["Sec-Fetch-Site"] = "same-origin"
  } else {
    headers["x-moongate-control-token"] = token
  }
  let client = @http.Client(origin, headers~)
  defer client.close()
  let response = match payload {
    Some(value) => client.post(prefix + path, value.stringify())
    None => client.get(prefix + path)
  }
  guard response.code >= 200 && response.code < 300 else {
    raise Failure("MoonGate rejected the request")
  }
  let bytes = @buffer.Buffer(size_hint=1024)
  for ;; {
    guard client.read_some(max_len=(65537 - bytes.length()).min(8192))
      is Some(chunk) else {
      break
    }
    bytes.write_bytes(chunk)
    if bytes.length() > 65536 {
      raise Failure("MoonGate response exceeded its limit")
    }
  }
  if bytes.length() == 0 {
    Json::empty_object()
  } else {
    @json.parse(@utf8.decode(bytes.to_bytes()))
  }
}

///|
async fn gate_control(workspace_root : String) -> GateControl? {
  guard @moongate.discover_from_suite_status_for_workspace_root(workspace_root)
    is Some(client) &&
    url_parts(client.base_url()) is Some((origin, prefix)) else {
    return None
  }
  let environment = @os.getenv("MOONGATE_CONTROL_TOKEN") catch { _ => None }
  let mut token = match environment {
    Some(value) if !value.trim().is_empty() => value.trim().to_owned()
    _ => {
      let path = @moonsuite.product_artifact_for_workspace_root(
        workspace_root, "moongate", "control-token",
      )
      @book_runtime.read_resource(path).unwrap_or("").trim().to_owned()
    }
  }
  if token.is_empty() {
    guard origin.has_prefix("http://127.0.0.1:") ||
      origin.has_prefix("http://localhost:") ||
      origin.has_prefix("http://[::1]:") else {
      return None
    }
    let bootstrap = gate_request(
      origin,
      prefix,
      "",
      "/control/bootstrap",
      None,
      bootstrap=true,
    )
    guard bootstrap is { "token": String(value), .. } else { return None }
    token = value
  }
  if token.is_empty() ||
    token.length() > 4096 ||
    !token.all(c => c > ' ' && c <= '~') {
    None
  } else {
    Some({ origin, prefix, token, })
  }
}

///|
/// Import an operator-supplied OpenAI connection through this workspace's
/// MoonGate. Validation is transient and must succeed before any provider
/// listing or mutation. Later configuration errors preserve existing MoonGate
/// partial-success semantics; this operation does not invent a rollback.
/// All requests are finite, capped at 64 KiB per response and 30 seconds total.
pub async fn import_connection(
  workspace_root : String,
  descriptor : Json,
) -> Result[Json, ImportError] {
  guard candidate_from_json(descriptor) is Some(candidate) else {
    return Err(InvalidDescriptor)
  }
  let mut stage = "MoonGate discovery"
  @async.with_timeout(30000, () => {
    guard gate_control(workspace_root) is Some(control) else {
      return Err(GateUnavailable)
    }
    stage = "connection validation"
    let validation = gate_request(
      control.origin,
      control.prefix,
      control.token,
      "/providers/validate-connection",
      Some({
        "appType": "openclaw",
        "api": candidate.api,
        "baseUrl": candidate.base_url,
        "apiKey": candidate.api_key,
        "model": candidate.model,
      }),
    )
    guard validation
      is {
        "contract": "moongate.provider-connection-validation.v1",
        "valid": True,
        "model": String(model),
        "inferencePerformed": False,
        "persisted": False,
        ..
      } &&
      model == candidate.model &&
      !validation.stringify().contains(candidate.api_key) else {
      return Err(Failed("connection validation"))
    }
    stage = "provider listing"
    let listed = gate_request(
      control.origin,
      control.prefix,
      control.token,
      "/providers?appType=openclaw",
      None,
    )
    let id = provider_id(candidate)
    stage = "provider configuration"
    let path = if provider_exists(listed, id) {
      "/providers/update"
    } else {
      "/providers"
    }
    let _ = gate_request(
      control.origin,
      control.prefix,
      control.token,
      path,
      Some({
        "appType": "openclaw",
        "id": id,
        "name": "Imported " + candidate.model,
        "enabled": true,
        "providerType": "openai-compatible",
        "apiFormat": "openai_chat",
        "baseUrl": candidate.base_url,
        "apiKey": candidate.api_key,
        "defaultModel": candidate.model,
        "notes": "Imported from a reviewed OpenAI connection descriptor",
      }),
    )
    stage = "provider activation"
    let _ = gate_request(
      control.origin,
      control.prefix,
      control.token,
      "/providers/switch",
      Some({ "appType": "openclaw", "id": id }),
    )
    stage = "runtime binding"
    let _ = gate_request(
      control.origin,
      control.prefix,
      control.token,
      "/bindings",
      Some({ "appType": "moondesk", "providerId": id }),
    )
    Ok({
      "contract": "moonclaw.provider-connection-import.v1",
      "ok": true,
      "status": "connected",
      "model": candidate.model,
      "provider_id": id,
    })
  }) catch {
    _ => Err(Failed(stage))
  }
}
