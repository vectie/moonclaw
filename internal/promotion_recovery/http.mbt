///|
fn token_equal(left : String, right : String) -> Bool {
  let mut difference = left.length() ^ right.length()
  for i in 0..<right.length() {
    difference = difference |
      (
        (if i < left.length() { left[i].to_int() } else { 0 }) ^
        right[i].to_int()
      )
  }
  difference == 0
}

///|
async fn reply(w : @httpx.ResponseWriter, status : Int, value : Json) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.header().set("Cache-Control", "no-store")
  w.write_header(status)
  w.write(value.stringify())
}

///|
/// Shared bounded read-only route used by the daemon and authenticated gateway.
pub async fn handle(
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let config = @moondesk_sandbox_config.load(read_only=true) catch { _ => None }
  guard config is Some(config) else {
    reply(w, 503, {
      "error": {
        "code": "recovery_unavailable",
        "message": "The private inspection route is unavailable.",
      },
    })
    return
  }
  guard token_equal(
    r.headers.get("x-moonclaw-execution-token").unwrap_or(""),
    config.auth_token,
  ) else {
    reply(w, 401, {
      "error": {
        "code": "unauthorized",
        "message": "Inspection authentication failed.",
      },
    })
    return
  }
  let request = try {
    let bytes = @buffer.Buffer(size_hint=1024)
    for ;; {
      guard r.body.read_some(max_len=(4097 - bytes.length()).min(2048))
        is Some(chunk) else {
        break
      }
      guard bytes.length() + chunk.length() <= 4096 else { fail("bound") }
      bytes.write_bytes(chunk)
    }
    moondesk_recovery_parse_request(
      @json.parse(@encoding/utf8.decode(bytes.to_bytes())),
    )
  } catch {
    _ => {
      reply(w, 422, {
        "error": {
          "code": "invalid_request",
          "message": "Only bounded exact pending return identifiers are accepted.",
        },
      })
      return
    }
  }
  let result = read_moondesk_recovery(request, config) catch {
    _ => {
      reply(w, 503, {
        "error": {
          "code": "recovery_unavailable",
          "message": "The exact pending return could not be safely inspected. It remains unresolved; no return was retried.",
        },
      })
      return
    }
  }
  reply(w, 200, result)
}
