///|
/// Registers a task process with the daemon.
///
/// Endpoint: POST /v1/task/register
///
/// Request:
///
/// - Body: JSON `RegisterRequest` containing the task `id` and listening `port`.
///
/// Response:
///
/// - 200 OK: JSON `RegisterResponse` confirming registration.
///
/// Errors:
///
/// - 400 Bad Request: Invalid UTF-8, invalid JSON, or cannot decode `RegisterRequest`.
#warnings("-unnecessary_annotation")
async fn Daemon::register_task(
  self : Daemon,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let pending = authorize_task_registration(
    self.rqs,
    r.headers,
    self.clock.now().ms(),
  )
  let request_bytes = r.body.read_all().binary()
  let request_text = @encoding/utf8.decode(request_bytes) catch {
    Malformed(bytes) =>
      raise json_error(
        400,
        "Bad Request",
        "Invalid UTF-8 in request body: \{bytes}",
      )
  }
  let request_json = @json.parse(request_text) catch {
    error =>
      raise json_error(
        400,
        "Bad Request",
        "Invalid JSON in request body: \{error}",
      )
  }
  let register : @server.RegisterRequest = @json.from_json(request_json) catch {
    error =>
      raise json_error(
        400,
        "Bad Request",
        "Failed to decode RegisterRequest: \{error}",
      )
  }
  guard register.id ==
    r.headers.get("x-moonclaw-worker-registration-instance").unwrap_or("") else {
    raise worker_registration_error()
  }
  logger.info("Registered authenticated task on port \{register.port}")
  pending.queue.put(register)
  w.write_header(200)
  let res : @server.RegisterResponse = @server.RegisterResponse::{  }
  w.write(res.to_json())
}

///|
fn worker_registration_error() -> HttpError {
  json_error(401, "Unauthorized", {
    "error": {
      "code": "worker_registration_unauthorized",
      "message": "Worker registration authentication failed",
    },
  })
}

///|
fn authorize_task_registration(
  registrations : Map[String, PendingTaskRegistration],
  headers : Map[String, String],
  now_ms : Int64,
) -> PendingTaskRegistration raise HttpError {
  let instance_id = headers
    .get("x-moonclaw-worker-registration-instance")
    .unwrap_or("")
  let provided_token = headers
    .get("x-moonclaw-worker-registration-token")
    .unwrap_or("")
  let pending = registrations.get(instance_id)
  let expected_token = pending
    .map(pending => pending.token)
    .unwrap_or("0".repeat(72))
  let token_matches = moondesk_sandbox_constant_time_equal(
    provided_token, expected_token,
  )
  let expected_instance = pending
    .map(pending => pending.instance_id)
    .unwrap_or("0".repeat(36))
  let instance_matches = moondesk_sandbox_constant_time_equal(
    instance_id, expected_instance,
  )
  guard pending is Some(pending) &&
    token_matches &&
    instance_matches &&
    now_ms <= pending.expires_at_ms else {
    if pending is Some(pending) && now_ms > pending.expires_at_ms {
      registrations.remove(instance_id)
    }
    raise worker_registration_error()
  }
  // Consume before any body parsing or queue write. Concurrent requests cannot
  // reuse the capability, and malformed authenticated input also burns it.
  registrations.remove(instance_id)
  pending
}
