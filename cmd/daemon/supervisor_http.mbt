///|
fn supervisor_query_component(value : String) -> String {
  let encoded = StringBuilder::new()
  for character in value {
    match character {
      'A'..='Z' | 'a'..='z' | '0'..='9' | '-' | '_' | '.' | '~' =>
        encoded.write_char(character)
      _ => {
        let bytes = @encoding/utf8.encode(character.to_string())
        for byte in bytes {
          let number = byte.to_int()
          let hex = fn(n : Int) -> Char {
            if n < 10 {
              ('0'.to_int() + n).unsafe_to_char()
            } else {
              ('A'.to_int() + n - 10).unsafe_to_char()
            }
          }
          encoded.write_char('%')
          encoded.write_char(hex((number >> 4) & 0xF))
          encoded.write_char(hex(number & 0xF))
        }
      }
    }
  }
  encoded.to_string()
}

///|
fn supervisor_runtime_model_selector(policy_model : String) -> String {
  match policy_model.trim() {
    "gpt-5.6-sol" => "codex/gpt-5.6-sol"
    selector => selector.to_owned()
  }
}

///|
fn daemon_supervisor_authority_verifier(
  home : String,
) -> @job.SupervisorAuthorityVerifierV1 {
  @job.SupervisorAuthorityVerifierV1::new(verify=async fn(envelope, expected) {
    let client = match
      @moongate.discover_from_suite_status_for_workspace_root(home) {
      Some(client) => client
      None => return Err("MoonGate suite status is unavailable")
    }
    let slash = expected.find("/").unwrap_or(-1)
    let at = expected.rev_find("@").unwrap_or(-1)
    guard slash > 0 && at > slash + 1 else {
      return Err("invalid exact operation reference")
    }
    let product_id = expected[:slash].to_owned()
    let operation_id = expected[slash + 1:at].to_owned()
    let path = "/suite/capabilities/resolve?productId=\{product_id}" +
      "&operationId=\{operation_id}" +
      "&requestedAuthority=WorkspaceMutation" +
      "&root=\{supervisor_query_component(home)}"
    let resolution = match client.get(path) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    guard resolution
      is {
        "contract": "moonsuite.capability-resolution.v1",
        "productId": String(resolved_product),
        "operationId": String(resolved_operation),
        "executable": true,
        "operation": operation,
        ..
      } &&
      resolved_product == product_id &&
      resolved_operation == operation_id else {
      return Err("exact MoonGate operation is not executable")
    }
    let digest = @capability.sha256_digest_ref_v1(
      @encoding/utf8.encode(operation.stringify()),
    ).text()
    Ok({
      operation_ref: expected,
      operation_digest: digest,
      capability_resolution: resolution,
      verified_at: envelope.evaluated_at,
    })
  })
}

///|
let daemon_supervisor_runtimes : Map[String, @job.SupervisorRuntime] = Map([])

///|
/// Process-retained registry keeps supervisor state out of the broad Daemon
/// record, whose many focused test fixtures intentionally construct it
/// directly. Durable truth remains the per-home journal.
async fn Daemon::supervisor_runtime(self : Daemon) -> @job.SupervisorRuntime {
  match daemon_supervisor_runtimes.get(self.home) {
    Some(value) => value
    None => {
      let receiver = @capability.principal_ref_v1(
        "moonclaw-daemon",
        Service,
        "moonclaw",
        "local-daemon",
      )
      let value = @job.SupervisorRuntime::new(
        runtime=@job.RuntimeManager::new(
          root=@job.moonclaw_jobs_root(self.home),
        ),
        receiver~,
        verifier=daemon_supervisor_authority_verifier(self.home),
      )
      value.load()
      daemon_supervisor_runtimes.set(self.home, value)
      value
    }
  }
}

///|
async fn supervisor_http_json(
  w : @httpx.ResponseWriter,
  status : Int,
  value : Json,
) -> Unit {
  w.header().set("Content-Type", "application/json")
  w.write_header(status)
  w.write(value.stringify(indent=2))
}

///|
async fn supervisor_http_body(r : @httpx.RequestReader) -> Json {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  reader.read() catch {
    _ =>
      raise json_error(400, "Bad Request", {
        "error": { "code": "invalid_json", "message": "Invalid JSON body" },
      })
  }
}

///|
fn supervisor_http_failure(error : String) -> HttpError {
  let code = if error.contains("unknown supervisor") {
    404
  } else if error.contains("stale") || error.contains("duplicate") {
    409
  } else if error.contains("authority") || error.contains("MoonGate") {
    403
  } else {
    400
  }
  json_error(code, "Supervisor Command Rejected", {
    "error": { "code": "supervisor_command_rejected", "message": error },
  })
}

///|
async fn Daemon::supervisor_activate(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let request : @job.SupervisorActivateRequestV1 = @json.from_json(
    supervisor_http_body(r),
  ) catch {
    error =>
      raise json_error(400, "Bad Request", {
        "error": { "code": "invalid_activation", "message": "\{error}" },
      })
  }
  let supervisors = self.supervisor_runtime()
  let duplicate = match supervisors.verify_activation(request) {
    Err(error) => raise supervisor_http_failure(error)
    Ok(value) => value is Some(_)
  }
  let (task, created) = self.ensure_supervisor_task(group~, request.profile)
  // New versions must be installed successfully before journal acceptance.
  // A duplicate only reinstalls when recovery had to respawn its executor.
  if !duplicate || created {
    self.install_supervisor_profile(task, request.profile)
  }
  let receipt = match
    supervisors.activate_profile(request, task.id.to_string()) {
    Ok(value) => value
    Err(error) => raise supervisor_http_failure(error)
  }
  self.drain_supervisor_mailbox(task, request.profile.supervisor_id)
  supervisor_http_json(w, 200, receipt.to_json())
}

///|
async fn Daemon::install_supervisor_profile(
  self : Daemon,
  task : Running,
  profile : @job.SupervisorProfileActivationV1,
) -> Unit {
  ignore(self)
  let exact_profile = profile.runtime_profile.stringify()
  let digest = @capability.sha256_digest_ref_v1(
    @encoding/utf8.encode(exact_profile),
  ).text()
  guard digest == profile.profile_digest else {
    raise supervisor_http_failure(
      "runtime profile digest changed before install",
    )
  }
  let (response, body) = @httpx.post_json(
    "http://127.0.0.1:\{task.port}/v1/system-prompt",
    exact_profile.to_json(),
  )
  guard response.code is (200..=299) else {
    raise supervisor_http_failure(
      "canonical supervisor profile installation failed: \{body.text()}",
    )
  }
}

///|
async fn Daemon::ensure_supervisor_task(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  profile : @job.SupervisorProfileActivationV1,
) -> (Running, Bool) {
  let name = "supervisor:\{profile.supervisor_id}"
  let model_name = match profile.runtime_binding {
    { "model": String(value), .. } if !value.trim().is_blank() => value
    _ =>
      raise supervisor_http_failure(
        "immutable supervisor runtime binding must declare an exact model",
      )
  }
  let model_selector = supervisor_runtime_model_selector(model_name)
  let model = match self.models.get_model(name=model_selector) {
    Some(value) => value
    None =>
      raise supervisor_http_failure(
        "immutable supervisor model is unavailable: \{model_name}",
      )
  }
  for task in self.by_id.values() {
    match task {
      Running(running) if running.name == Some(name) => {
        guard running.model == model.name else {
          raise supervisor_http_failure(
            "running supervisor model does not match immutable binding",
          )
        }
        return (running, false)
      }
      Stopped(stopped) if stopped.name == Some(name) => {
        let cwd = stopped.cwd
        guard @fsx.exists(cwd) else {
          raise supervisor_http_failure(
            "canonical supervisor executor working directory is missing",
          )
        }
        let task_list = self.by_cwd.get_or_init(cwd, () => TaskLock::new())
        task_list.spawn_mutex.acquire()
        defer task_list.spawn_mutex.release()
        match task_list.running {
          Some(task) => {
            guard task.model == model.name else {
              raise supervisor_http_failure(
                "running supervisor model does not match immutable binding",
              )
            }
            return (task, false)
          }
          None => {
            let resumed = self.spawn_task(
              group~,
              name?=stopped.name,
              model~,
              cwd=stopped.cwd,
              resume_id=stopped.id,
              broadcast=stopped.broadcast,
            )
            guard resumed.model == model.name else {
              raise supervisor_http_failure(
                "resumed supervisor did not register the immutable model",
              )
            }
            task_list.running = Some(resumed)
            return (resumed, true)
          }
        }
      }
      _ => ()
    }
  }
  let cwd = @job.moonclaw_jobs_root(self.home)
    |> @pathx.join("supervisor-executors")
    |> @pathx.join(profile.supervisor_id)
  @fsx.make_directory(cwd, recursive=true, exists_ok=true)
  let task_list = self.by_cwd.get_or_init(cwd, () => TaskLock::new())
  task_list.spawn_mutex.acquire()
  defer task_list.spawn_mutex.release()
  match task_list.running {
    Some(task) => {
      guard task.model == model.name else {
        raise supervisor_http_failure(
          "running supervisor model does not match immutable binding",
        )
      }
      (task, false)
    }
    None => {
      let task = self.spawn_task(group~, name~, model~, cwd~)
      guard task.model == model.name else {
        raise supervisor_http_failure(
          "supervisor did not register the immutable model",
        )
      }
      task_list.running = Some(task)
      (task, true)
    }
  }
}

///|
async fn Daemon::supervisor_executor_owner(
  self : Daemon,
  executor_run_id : String,
) -> String? {
  let supervisors = self.supervisor_runtime()
  for status in supervisors.list_status() {
    if status.state.active_run_id == Some(executor_run_id) {
      return Some(status.state.supervisor_id)
    }
  }
  None
}

///|
fn Daemon::running_supervisor_task(
  self : Daemon,
  supervisor_id : String,
) -> Running? {
  let name = Some("supervisor:\{supervisor_id}")
  for task in self.by_id.values() {
    match task {
      Running(running) if running.name == name => return Some(running)
      _ => ()
    }
  }
  None
}

///|
async fn Daemon::drain_supervisor_mailbox(
  self : Daemon,
  task : Running,
  supervisor_id : String,
) -> Unit {
  let now_ms = @job.supervisor_epoch_ms_v1(self.clock.now().ms())
  let supervisors = self.supervisor_runtime()
  for message in supervisors.pending_mailbox(supervisor_id, now_ms) {
    ignore(
      task.create_message(
        @server.CreateMessageRequest::new(
          message=@ai.user_message(content=message.content),
          web_search=false,
        ),
      ),
    )
    match
      supervisors.record_message_delivery(
        supervisor_id,
        message.message_id,
        task.id.to_string(),
        now_ms,
      ) {
      Ok(_) => ()
      Err(error) => fail("failed to acknowledge supervisor delivery: \{error}")
    }
  }
}

///|
async fn Daemon::restore_supervisors(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
) -> Unit {
  let supervisors = self.supervisor_runtime()
  for status in supervisors.list_status() {
    match status.state.lifecycle {
      Stopped | Failed => ()
      Dormant | Running =>
        ignore(self.restore_one_supervisor(group~, status.state.supervisor_id)) catch {
          error =>
            logger.error(
              "Failed to restore supervisor \{status.state.supervisor_id}: \{error}",
            )
        }
    }
  }
}

///|
/// Restores or resumes the exact daemon task bound into the durable supervisor
/// state. A different UUID is never silently accepted as the executor.
async fn Daemon::restore_one_supervisor(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  supervisor_id : String,
) -> Running {
  let supervisors = self.supervisor_runtime()
  let status = match supervisors.status(supervisor_id) {
    Ok(value) => value
    Err(error) => raise supervisor_http_failure(error)
  }
  let expected_id = match status.state.active_run_id {
    Some(value) => value
    None =>
      raise supervisor_http_failure("supervisor has no canonical executor")
  }
  let (task, created) = self.ensure_supervisor_task(
    group~,
    status.state.profile,
  )
  guard task.id.to_string() == expected_id else {
    raise supervisor_http_failure(
      "canonical supervisor executor identity changed; explicit reactivation is required",
    )
  }
  if created {
    self.install_supervisor_profile(task, status.state.profile)
  }
  self.drain_supervisor_mailbox(task, supervisor_id)
  task
}

///|
async fn Daemon::supervisor_send_message(
  self : Daemon,
  expected_supervisor_id : String,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let request : @job.SupervisorSendMessageRequestV1 = @json.from_json(
    supervisor_http_body(r),
  ) catch {
    error =>
      raise json_error(400, "Bad Request", {
        "error": { "code": "invalid_message", "message": "\{error}" },
      })
  }
  if request.supervisor_id != expected_supervisor_id {
    raise supervisor_http_failure("supervisor path identity mismatch")
  }
  let supervisors = self.supervisor_runtime()
  let receipt = match supervisors.send_message(request) {
    Ok(value) => value
    Err(error) => raise supervisor_http_failure(error)
  }
  // Delivery is outbox-driven: the durable command is accepted first, and an
  // unavailable executor simply leaves the message pending for wake/recovery.
  match self.running_supervisor_task(request.supervisor_id) {
    Some(task) => self.drain_supervisor_mailbox(task, request.supervisor_id)
    None => ()
  }
  supervisor_http_json(w, 200, receipt.to_json())
}

///|
async fn Daemon::supervisor_command(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  expected_supervisor_id : String,
  kind : String,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = supervisor_http_body(r)
  let supervisors = self.supervisor_runtime()
  guard body is { "supervisor_id": String(body_supervisor_id), .. } &&
    body_supervisor_id == expected_supervisor_id else {
    raise supervisor_http_failure("supervisor path identity mismatch")
  }
  let result : Result[@job.SupervisorCommandReceiptV1, String] = try {
    match kind {
      "wake" => {
        let request : @job.SupervisorWakeRequestV1 = @json.from_json(body)
        let receipt = supervisors.wake_resume(request)
        match receipt {
          Ok(value) => {
            ignore(self.restore_one_supervisor(group~, request.supervisor_id))
            Ok(value)
          }
          Err(error) => Err(error)
        }
      }
      "steer" => {
        let request : @job.SupervisorSteerRequestV1 = @json.from_json(body)
        let receipt = supervisors.steer(request)
        match receipt {
          Ok(value) => {
            match self.running_supervisor_task(request.supervisor_id) {
              Some(task) =>
                self.drain_supervisor_mailbox(task, request.supervisor_id)
              None => ()
            }
            Ok(value)
          }
          Err(error) => Err(error)
        }
      }
      "stop" => {
        let request : @job.SupervisorStopRequestV1 = @json.from_json(body)
        let task = self.running_supervisor_task(request.supervisor_id)
        let receipt = supervisors.stop_cancel(request)
        match receipt {
          Ok(value) => {
            // A duplicate retry can recover from a prior transport failure,
            // so cancellation of the same canonical task is re-issued.
            match task {
              Some(running) => {
                let (response, body) = @httpx.post_json(
                  "http://127.0.0.1:\{running.port}/v1/cancel",
                  {},
                )
                guard response.code is (200..=299) else {
                  raise supervisor_http_failure(
                    "canonical supervisor executor cancellation failed: \{body.text()}",
                  )
                }
              }
              None => ()
            }
            Ok(value)
          }
          Err(error) => Err(error)
        }
      }
      "retry-resume" => {
        let request : @job.SupervisorRetryResumeRequestV1 = @json.from_json(
          body,
        )
        let receipt = supervisors.retry_resume(request)
        match receipt {
          Ok(value) => {
            ignore(self.restore_one_supervisor(group~, request.supervisor_id))
            Ok(value)
          }
          Err(error) => Err(error)
        }
      }
      "delegate-existing" => {
        let request : @job.SupervisorDelegateExistingRequestV1 = @json.from_json(
          body,
        )
        supervisors.delegate_existing(request)
      }
      "mailbox-claim" => {
        let request : @job.SupervisorMailboxClaimRequestV1 = @json.from_json(
          body,
        )
        supervisors.claim_mailbox(request)
      }
      "mailbox-ack" => {
        let request : @job.SupervisorMailboxAckRequestV1 = @json.from_json(body)
        supervisors.ack_mailbox(request)
      }
      "outcome-evidence" => {
        let request : @job.SupervisorOutcomeEvidenceRequestV1 = @json.from_json(
          body,
        )
        supervisors.emit_outcome_evidence(request)
      }
      "outbox-claim" => {
        let request : @job.SupervisorOutcomeOutboxClaimRequestV1 = @json.from_json(
          body,
        )
        supervisors.claim_outcome_outbox(request)
      }
      "outbox-ack" => {
        let request : @job.SupervisorOutcomeOutboxAckRequestV1 = @json.from_json(
          body,
        )
        supervisors.ack_outcome_outbox(request)
      }
      _ => Err("unsupported supervisor command")
    }
  } catch {
    error =>
      raise json_error(400, "Bad Request", {
        "error": { "code": "invalid_command", "message": "\{error}" },
      })
  }
  match result {
    Ok(receipt) => supervisor_http_json(w, 200, receipt.to_json())
    Err(error) => raise supervisor_http_failure(error)
  }
}

///|
async fn Daemon::supervisor_status(
  self : Daemon,
  supervisor_id : String,
  w : @httpx.ResponseWriter,
) -> Unit {
  let supervisors = self.supervisor_runtime()
  match supervisors.status(supervisor_id) {
    Ok(value) => supervisor_http_json(w, 200, value.to_json())
    Err(error) => raise supervisor_http_failure(error)
  }
}

///|
async fn Daemon::supervisor_replay(
  self : Daemon,
  supervisor_id : String,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let supervisors = self.supervisor_runtime()
  match
    supervisors.replay(
      supervisor_id,
      after_cursor=mooncode_request_int(r, "after_cursor", default=0),
      limit=mooncode_request_int(r, "limit", default=100),
    ) {
    Ok(value) => supervisor_http_json(w, 200, value.to_json())
    Err(error) => raise supervisor_http_failure(error)
  }
}
