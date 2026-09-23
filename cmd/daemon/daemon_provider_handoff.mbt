///|
const LUNANEXA_HANDOFF_REQUEST_BYTES : Int = 2_048

///|
const LUNANEXA_HANDOFF_RESPONSE_BYTES : Int = 65_536

///|
priv struct LunaProviderHandoffRequest {
  contract : String
  client_id : String
  handoff_code : String
} derive(FromJson)

///|
priv struct LunaProviderHandoffRedemption {
  client_id : String
  api_secret : String
  api_base_url : String
  allowed_models : Array[String]
  expires_unix_ms : Int64
  maximum_requests : Int64
  one_time : Bool
} derive(FromJson)

///|
fn lunanexa_identifier(value : String, maximum : Int) -> Bool {
  value.length() > 0 &&
  value.length() <= maximum &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    ['-', '_', '.', ':'].contains(character)
  })
}

///|
fn lunanexa_valid_port(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 5 &&
  value.all(character => character.is_ascii_digit())
}

///|
fn lunanexa_loopback_authority(authority : String) -> Bool {
  let lower = authority.to_lower()
  if lower == "localhost" || lower == "127.0.0.1" || lower == "[::1]" {
    return true
  }
  for prefix in ["localhost:", "127.0.0.1:", "[::1]:"] {
    if lower.has_prefix(prefix) {
      return lunanexa_valid_port(lower[prefix.length():].to_owned())
    }
  }
  false
}

///|
fn lunanexa_url_origin(
  value : String,
  origin_only : Bool,
  allow_public_http? : Bool = false,
) -> String? {
  if value == "" ||
    value.length() > 2_048 ||
    value.trim() != value ||
    value.contains_char('@') ||
    value.contains_char('\\') ||
    value.contains_char('?') ||
    value.contains_char('#') ||
    value.contains_char('\n') ||
    value.contains_char('\r') {
    return None
  }
  let (secure, scheme, remainder) = if value.has_prefix("https://") {
    (true, "https://", value[8:].to_owned())
  } else if value.has_prefix("http://") {
    (false, "http://", value[7:].to_owned())
  } else {
    return None
  }
  let (authority, path) = match remainder.find("/") {
    Some(index) => (remainder[:index].to_owned(), remainder[index:].to_owned())
    None => (remainder, "")
  }
  if authority == "" ||
    authority.length() > 255 ||
    !authority.all(character => {
      (character >= 'a' && character <= 'z') ||
      (character >= 'A' && character <= 'Z') ||
      (character >= '0' && character <= '9') ||
      ['-', '.', ':', '[', ']'].contains(character)
    }) ||
    (
      origin_only &&
      path != "" &&
      path != "/" &&
      path != "/user" &&
      path != "/user/"
    ) ||
    (!secure && !allow_public_http && !lunanexa_loopback_authority(authority)) {
    return None
  }
  let prefix = if origin_only && (path == "/user" || path == "/user/") {
    "/user"
  } else {
    ""
  }
  Some(scheme + authority + prefix)
}

///|
fn configured_lunanexa_issuer() -> String? {
  let configured = @os.getenv("MOONDESK_LUNANEXA_ISSUER") catch { _ => None }
  guard configured is Some(raw) else { return None }
  let allow_public_http = (@os.getenv("MOONDESK_LUNANEXA_HTTP_ALLOWED") catch {
      _ => None
    }) ==
    Some("true")
  lunanexa_url_origin(raw.trim().to_owned(), true, allow_public_http~)
}

///|
fn valid_lunanexa_redemption(
  value : LunaProviderHandoffRedemption,
  request : LunaProviderHandoffRequest,
  issuer : String,
  now_unix_ms : Int64,
) -> Bool {
  value.client_id == request.client_id &&
  value.one_time &&
  value.api_secret.length() == 68 &&
  value.api_secret.has_prefix("lnx_") &&
  value.api_secret[4:].all(character => character.is_ascii_hexdigit()) &&
  value.allowed_models.length() > 0 &&
  value.allowed_models.length() <= 128 &&
  value.allowed_models.all(model => lunanexa_identifier(model, 128)) &&
  value.expires_unix_ms > now_unix_ms &&
  value.maximum_requests > 0L &&
  lunanexa_url_origin(issuer, false, allow_public_http=true) is Some(origin) &&
  lunanexa_url_origin(
    value.api_base_url,
    false,
    allow_public_http=issuer.has_prefix("http://") &&
      !lunanexa_loopback_authority(origin[7:].to_owned()),
  ) ==
  Some(origin) &&
  value.api_base_url == issuer + "/v1"
}

///|
fn valid_lunanexa_handoff_request(request : LunaProviderHandoffRequest) -> Bool {
  request.contract == "moonclaw.provider-handoff.v1" &&
  lunanexa_identifier(request.client_id, 256) &&
  request.handoff_code.length() == 69 &&
  request.handoff_code.has_prefix("lnxc_") &&
  request.handoff_code[5:].all(character => character.is_ascii_hexdigit())
}

///|
fn lunanexa_provider_handoff_success(
  redemption : LunaProviderHandoffRedemption,
) -> Json {
  {
    "ok": true,
    "status": "connected",
    "provider_id": "lunanexa-lease",
    "model": redemption.allowed_models[0],
    "expires_unix_ms": redemption.expires_unix_ms.to_json(),
    "maximum_requests": redemption.maximum_requests.to_json(),
  }
}

///|
async fn read_lunanexa_handoff_request(
  r : @httpx.RequestReader,
) -> LunaProviderHandoffRequest {
  let output = @buffer.Buffer(size_hint=512)
  for ;; {
    guard r.body.read_some(
        max_len=(LUNANEXA_HANDOFF_REQUEST_BYTES - output.length() + 1).min(
          1_024,
        ),
      )
      is Some(chunk) else {
      break
    }
    if output.length() + chunk.length() > LUNANEXA_HANDOFF_REQUEST_BYTES {
      raise json_error(413, "Payload Too Large", {
        "error": {
          "code": "handoff_too_large",
          "message": "Provider handoff exceeds the request limit",
        },
      })
    }
    output.write_bytes(chunk)
  }
  let value : LunaProviderHandoffRequest = @json.from_json(
    @json.parse(@encoding/utf8.decode(output.to_bytes())),
  ) catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": {
          "code": "invalid_handoff",
          "message": "Invalid provider handoff",
        },
      })
  }
  value
}

///|
async fn read_lunanexa_handoff_response(
  client : @http.Client,
) -> Result[String, String] {
  let output = @buffer.Buffer(size_hint=8_192)
  for ;; {
    let chunk = client.read_some(
      max_len=(LUNANEXA_HANDOFF_RESPONSE_BYTES - output.length() + 1).min(8_192),
    ) catch {
      _ => return Err("LunaNexa response could not be read")
    }
    guard chunk is Some(chunk) else { break }
    if output.length() + chunk.length() > LUNANEXA_HANDOFF_RESPONSE_BYTES {
      return Err("LunaNexa response exceeded the size limit")
    }
    output.write_bytes(chunk)
  }
  Ok(@encoding/utf8.decode(output.to_bytes())) catch {
    _ => Err("LunaNexa response was not valid UTF-8")
  }
}

///|
async fn redeem_lunanexa_provider_handoff(
  issuer : String,
  request : LunaProviderHandoffRequest,
) -> Result[LunaProviderHandoffRedemption, String] {
  guard lunanexa_url_origin(issuer, false, allow_public_http=true)
    is Some(origin) else {
    return Err("LunaNexa issuer is unavailable")
  }
  let prefix = issuer[origin.length():].to_owned()
  let client = @http.Client(origin, headers={
    "Accept": "application/json",
    "Content-Type": "application/json",
  }) catch {
    _ => return Err("LunaNexa issuer is unavailable")
  }
  defer client.close()
  let response = client.post(
    prefix + "/v1/client-handoffs:redeem",
    (
      { "client_id": request.client_id, "handoff_code": request.handoff_code } :
      Json),
  ) catch {
    _ => return Err("LunaNexa redemption request failed")
  }
  let body = match read_lunanexa_handoff_response(client) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if response.code < 200 || response.code >= 300 {
    return Err("LunaNexa rejected the one-time handoff")
  }
  let redemption : LunaProviderHandoffRedemption = @json.from_json(
    @json.parse(body),
  ) catch {
    _ => return Err("LunaNexa returned an invalid handoff receipt")
  }
  if !valid_lunanexa_redemption(redemption, request, issuer, @async.now()) {
    return Err("LunaNexa returned an unsafe handoff receipt")
  }
  Ok(redemption)
}

///|
async fn install_lunanexa_provider_handoff(
  workspace_root : String,
  issuer : String,
  request : LunaProviderHandoffRequest,
) -> Result[LunaProviderHandoffRedemption, String] {
  let redemption = match redeem_lunanexa_provider_handoff(issuer, request) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let client = match
    @moongate.discover_from_suite_status_for_workspace_root(workspace_root) {
    Some(value) => value
    None => return Err("MoonGate suite status is unavailable")
  }
  match
    client.configure_workspace_provider(
      redemption.api_base_url,
      redemption.api_secret,
      redemption.allowed_models[0],
    ) {
    Ok(_) => Ok(redemption)
    Err(_) => Err("MoonGate rejected provider installation")
  }
}

///|
async fn Daemon::provider_handoff(
  self : Daemon,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let request = read_lunanexa_handoff_request(r)
  if !valid_lunanexa_handoff_request(request) {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": "invalid_handoff",
        "message": "Invalid provider handoff",
      },
    })
  }
  guard configured_lunanexa_issuer() is Some(issuer) else {
    raise json_error(503, "Service Unavailable", {
      "error": {
        "code": "issuer_unavailable",
        "message": "The LunaNexa issuer is not configured",
      },
    })
  }
  let redemption = match
    install_lunanexa_provider_handoff(self.home, issuer, request) {
    Ok(value) => value
    Err(error) =>
      raise json_error(502, "Bad Gateway", {
        "error": { "code": "handoff_failed", "message": error },
      })
  }
  w.header().set("Content-Type", "application/json")
  w.header().set("Cache-Control", "no-store")
  w.write_header(200)
  w.write(lunanexa_provider_handoff_success(redemption).stringify())
}
