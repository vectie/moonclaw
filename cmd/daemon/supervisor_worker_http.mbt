///|
/// Host-only accounting configuration. This is deliberately outside every
/// Town/Desk request DTO and is resolved before provider dispatch.
fn configured_supervisor_worker_accounting_mode() -> String {
  let configured = @os.getenv("MOONCLAW_SUPERVISOR_WORKER_ACCOUNTING_MODE") catch {
    _ => None
  }
  match configured {
    Some(value) if !value.trim().is_blank() => value.trim().to_owned()
    _ => "unknown"
  }
}

///|
fn supervisor_worker_task_name(
  supervisor_id : String,
  request_digest : String,
) -> String {
  "supervisor-worker:\{supervisor_id}:\{request_digest[7:31]}"
}

///|
async fn Daemon::ensure_supervisor_worker_task(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  request : @job.SupervisorDelegateIntentRequestV1,
  expected_id? : String,
) -> Running {
  let name = supervisor_worker_task_name(
    request.supervisor_id,
    request.envelope.request_digest,
  )
  for task in self.by_id.values() {
    match task {
      Running(running) if running.name == Some(name) => {
        guard expected_id is None || expected_id == Some(running.id.to_string()) else {
          raise supervisor_http_failure(
            "durable worker provider identity changed",
          )
        }
        return running
      }
      Stopped(stopped) if stopped.name == Some(name) => {
        guard expected_id is None || expected_id == Some(stopped.id.to_string()) else {
          raise supervisor_http_failure(
            "durable worker provider identity changed",
          )
        }
        guard @fsx.exists(stopped.cwd) else {
          raise supervisor_http_failure(
            "durable worker provider working directory is missing",
          )
        }
        let task_list = self.by_cwd.get_or_init(stopped.cwd, () => {
          TaskLock::new()
        })
        task_list.spawn_mutex.acquire()
        defer task_list.spawn_mutex.release()
        match task_list.running {
          Some(other) =>
            if other.id == stopped.id {
              return other
            } else {
              raise supervisor_http_failure(
                "worker provider cwd is occupied by another task",
              )
            }
          None => {
            let resumed = self.spawn_task(
              group~,
              name?=stopped.name,
              cwd=stopped.cwd,
              resume_id=stopped.id,
              broadcast=stopped.broadcast,
            )
            task_list.running = Some(resumed)
            return resumed
          }
        }
      }
      _ => ()
    }
  }
  guard @fsx.exists(request.task.cwd) else {
    raise supervisor_http_failure(
      "governed worker target workspace does not exist",
    )
  }
  let worker_cwd = @job.moonclaw_jobs_root(self.home)
    |> @pathx.join("supervisor-workers")
    |> @pathx.join(request.envelope.request_digest[7:31])
  @fsx.make_directory(worker_cwd, recursive=true, exists_ok=true)
  let task_list = self.by_cwd.get_or_init(worker_cwd, () => TaskLock::new())
  task_list.spawn_mutex.acquire()
  defer task_list.spawn_mutex.release()
  match task_list.running {
    Some(_) =>
      raise supervisor_http_failure(
        "worker provider cwd is occupied by another task",
      )
    None => {
      let model_selector = match request.task.model {
        Some(policy_model) => supervisor_runtime_model_selector(policy_model)
        None =>
          raise supervisor_http_failure("worker provider model is required")
      }
      let model = match self.models.get_model(name=model_selector) {
        Some(value) => value
        None => raise supervisor_http_failure("worker provider model not found")
      }
      let resume_id = expected_id.map(id => {
        @uuid.parse(id) catch {
          _ =>
            raise supervisor_http_failure(
              "durable worker provider identity is invalid",
            )
        }
      })
      let task = self.spawn_task(
        group~,
        name~,
        model~,
        web_search=request.task.web_search,
        resume_id?,
        cwd=worker_cwd,
      )
      guard expected_id is None || expected_id == Some(task.id.to_string()) else {
        raise supervisor_http_failure(
          "resumed worker provider identity changed",
        )
      }
      task_list.running = Some(task)
      task
    }
  }
}

///|
fn supervisor_worker_prompt(
  request : @job.SupervisorDelegateIntentRequestV1,
  worker_run_id : String,
  retry_reason? : String,
) -> String {
  let retry = match retry_reason {
    Some(value) => "Recovery reason: \{value}\n"
    None => ""
  }
  (
    $|You are MoonClaw worker \{worker_run_id}, delegated by supervisor \{request.supervisor_id}.
    $|Task: \{request.task.title}
    $|Task ID: \{request.task.task_id}
    $|Governed target workspace: \{request.task.cwd}
    $|\{retry}Instruction:
    $|\{request.instruction}
    $|
    $|Bounded delegation scope (do not exceed):
    $|\{request.scope.to_json().stringify(indent=2)}
    $|
    $|Task metadata:
    $|\{request.task.metadata.stringify(indent=2)}
    $|
    $|Return one JSON object with summary and artifact_evidence. artifact_evidence must be an explicit array (empty when no artifacts); every item must contain artifact_ref and sha256 digest. If the verified artifacts contain every required field for an exact moonbook.bookkeeper.product_outcome_submission.v1 projection, you may also include it as outcome_evidence_candidate. Evidence reference IDs must be globally unique; every reference needs a nonblank version and provenance plus a canonical lowercase sha256 digest matching artifact_evidence. Each gap needs a nonblank summary and unique in-submission evidence IDs; present gaps use severity 1..5 and absent gaps use exactly 0. Submission identity and capability ID, version, digest, and summary must be complete. MoonBook observed_at/recorded_at are JSON integers. Omit the candidate when any field is incomplete. Do not claim review, acceptance, publication, or closure.
  )
}

///|
/// Emits the wire value required by the supervisor delegate-result contract.
/// MoonBit's generic `Option::to_json` uses an array representation, which is
/// not the object-or-null shape shared with MoonTown.
fn supervisor_provider_receipt_json(
  receipt : @job.SupervisorCommandReceiptV1?,
) -> Json {
  match receipt {
    Some(value) => value.to_json()
    None => Json::null()
  }
}

///|
fn Daemon::enforce_supervisor_worker_deadline(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  supervisor_id : String,
  worker_run_id : String,
  attempt : Int,
  delay_ms : Int,
) -> Unit {
  group.spawn_bg(
    () => {
      @async.sleep(delay_ms.max(0))
      let supervisors = self.supervisor_runtime()
      let status = match
        supervisors.worker_status(supervisor_id, worker_run_id) {
        Ok(value) => value
        Err(_) => return
      }
      if status.attempt != attempt || !(status.run_status is Running) {
        return
      }
      let task = match self.running_supervisor_worker_task(worker_run_id) {
        Some(value) => value
        None => return
      }
      let (response, response_body) = @httpx.post_json(
        "http://127.0.0.1:\{task.port}/v1/cancel",
        {},
      ) catch {
        error => {
          logger.error(
            "Failed to cancel worker at runtime ceiling \{worker_run_id}: \{error}",
          )
          return
        }
      }
      if !(response.code is (200..=299)) {
        logger.error(
          "Worker rejected runtime-ceiling cancellation \{worker_run_id}: \{response_body.text()}",
        )
        return
      }
      ignore(
        supervisors.record_worker_provider_terminal(
          supervisor_id,
          worker_run_id,
          false,
          "delegated worker exceeded max_runtime_ms",
          {
            "provider_task_id": worker_run_id,
            "runtime_budget_exceeded": true,
            "provider_cancellation": response_body.json(),
          },
          @job.supervisor_epoch_ms_v1(self.clock.now().ms()),
        ),
      ) catch {
        error =>
          logger.error(
            "Failed to persist worker runtime-ceiling result: \{error}",
          )
      }
    },
    allow_failure=true,
  )
}

///|
async fn Daemon::supervisor_delegate_intent(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  expected_supervisor_id : String,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let request : @job.SupervisorDelegateIntentRequestV1 = @json.from_json(
    supervisor_http_body(r),
  ) catch {
    error =>
      raise json_error(400, "Bad Request", {
        "error": { "code": "invalid_delegate_intent", "message": "\{error}" },
      })
  }
  guard request.supervisor_id == expected_supervisor_id else {
    raise supervisor_http_failure("supervisor path identity mismatch")
  }
  let supervisors = self.supervisor_runtime()
  let accounting_mode = configured_supervisor_worker_accounting_mode()
  let prior = match
    supervisors.verify_delegate_intent(request, accounting_mode) {
    Ok(value) => value
    Err(error) => raise supervisor_http_failure(error)
  }
  let expected_worker_id = prior.map(value => value.worker_run_id)
  let task = self.ensure_supervisor_worker_task(
    group~,
    request,
    expected_id?=expected_worker_id,
  )
  let prepared = match
    supervisors.delegate_intent(request, task.id.to_string(), accounting_mode) {
    Ok(value) => value
    Err(error) => raise supervisor_http_failure(error)
  }
  let provider_receipt : @job.SupervisorCommandReceiptV1? = match
    supervisors.worker_status(request.supervisor_id, prepared.worker_run_id) {
    Ok(status) if status.run_status is Pending => {
      let evidence : Json = if task.status is Busy {
        {
          "provider_task_id": task.id.to_string(),
          "accepted": true,
          "observed_status": "busy",
          "recovered": true,
          "accounting_mode": accounting_mode,
        }
      } else {
        let response = task.create_message(
          @server.CreateMessageRequest::new(
            message=@ai.user_message(
              content=supervisor_worker_prompt(request, prepared.worker_run_id),
            ),
            web_search=request.task.web_search,
          ),
        )
        {
          "provider_task_id": task.id.to_string(),
          "accepted": true,
          "message": response.to_json(),
          "accounting_mode": accounting_mode,
        }
      }
      match
        supervisors.record_worker_provider_acceptance(
          request.supervisor_id,
          prepared.worker_run_id,
          evidence,
          @job.supervisor_epoch_ms_v1(self.clock.now().ms()),
        ) {
        Ok(value) => Some(value)
        Err(error) => raise supervisor_http_failure(error)
      }
    }
    Ok(_) => None
    Err(error) => raise supervisor_http_failure(error)
  }
  let status = match
    supervisors.worker_status(request.supervisor_id, prepared.worker_run_id) {
    Ok(value) => value
    Err(error) => raise supervisor_http_failure(error)
  }
  if provider_receipt is Some(_) && status.run_status is Running {
    self.enforce_supervisor_worker_deadline(
      group~,
      request.supervisor_id,
      prepared.worker_run_id,
      status.attempt,
      request.scope.budget.max_runtime_ms.to_int(),
    )
  }
  supervisor_http_json(w, 200, {
    "contract_id": "moonclaw.supervisor-delegate-intent-result.v1",
    "receipt": prepared.receipt,
    "provider_receipt": supervisor_provider_receipt_json(provider_receipt),
    "worker": status,
  })
}

///|
fn Daemon::running_supervisor_worker_task(
  self : Daemon,
  worker_run_id : String,
) -> Running? {
  let id = @uuid.parse(worker_run_id) catch { _ => return None }
  match self.by_id.get(id) {
    Some(Running(task)) => Some(task)
    _ => None
  }
}

///|
async fn Daemon::supervisor_worker_command(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
  expected_supervisor_id : String,
  kind : String,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let body = supervisor_http_body(r)
  let supervisors = self.supervisor_runtime()
  let receipt : @job.SupervisorCommandReceiptV1 = try {
    match kind {
      "worker-steer" => {
        let request : @job.SupervisorWorkerSteerRequestV1 = @json.from_json(
          body,
        )
        guard request.supervisor_id == expected_supervisor_id else {
          raise supervisor_http_failure("supervisor path identity mismatch")
        }
        match supervisors.verify_worker_steer(request) {
          Err(error) => raise supervisor_http_failure(error)
          Ok(Some(receipt)) => receipt
          Ok(None) => {
            let task = match
              self.running_supervisor_worker_task(request.worker_run_id) {
              Some(value) => value
              None =>
                raise supervisor_http_failure(
                  "target worker provider is not running",
                )
            }
            let (response, response_body) = @httpx.post_json(
              "http://127.0.0.1:\{task.port}/v1/external-event/user-message",
              { "message": request.instruction },
            )
            guard response.code is (200..=299) else {
              raise supervisor_http_failure(
                "worker provider rejected steer: \{response_body.text()}",
              )
            }
            match
              supervisors.worker_steer(request, {
                "provider_task_id": task.id.to_string(),
                "response": response_body.json(),
              }) {
              Ok(value) => value
              Err(error) => raise supervisor_http_failure(error)
            }
          }
        }
      }
      "worker-stop" => {
        let request : @job.SupervisorWorkerStopRequestV1 = @json.from_json(body)
        guard request.supervisor_id == expected_supervisor_id else {
          raise supervisor_http_failure("supervisor path identity mismatch")
        }
        match supervisors.verify_worker_stop(request) {
          Err(error) => raise supervisor_http_failure(error)
          Ok(Some(receipt)) => receipt
          Ok(None) => {
            let task = match
              self.running_supervisor_worker_task(request.worker_run_id) {
              Some(value) => value
              None =>
                raise supervisor_http_failure(
                  "target worker provider is not running",
                )
            }
            let worker_status = match
              supervisors.worker_status(
                request.supervisor_id,
                request.worker_run_id,
              ) {
              Ok(value) => value
              Err(error) => raise supervisor_http_failure(error)
            }
            let cancel_path = if worker_status.run_status is Running {
              "/v1/cancel"
            } else {
              "/v1/external-event/cancel"
            }
            let (response, response_body) = @httpx.post_json(
              "http://127.0.0.1:\{task.port}\{cancel_path}",
              {},
            )
            guard response.code is (200..=299) else {
              raise supervisor_http_failure(
                "worker provider rejected stop: \{response_body.text()}",
              )
            }
            match
              supervisors.worker_stop(request, {
                "provider_task_id": task.id.to_string(),
                "response": response_body.json(),
              }) {
              Ok(value) => value
              Err(error) => raise supervisor_http_failure(error)
            }
          }
        }
      }
      "worker-retry-resume" => {
        let request : @job.SupervisorWorkerRetryRequestV1 = @json.from_json(
          body,
        )
        guard request.supervisor_id == expected_supervisor_id else {
          raise supervisor_http_failure("supervisor path identity mismatch")
        }
        match supervisors.verify_worker_retry(request) {
          Err(error) => raise supervisor_http_failure(error)
          Ok(Some(receipt)) => receipt
          Ok(None) => {
            let intent = match
              supervisors.worker_intent(
                request.supervisor_id,
                request.worker_run_id,
              ) {
              Ok(value) => value
              Err(error) => raise supervisor_http_failure(error)
            }
            let task = self.ensure_supervisor_worker_task(
              group~,
              intent,
              expected_id=request.worker_run_id,
            )
            let provider_evidence : Json = if task.status is Busy {
              {
                "provider_task_id": task.id.to_string(),
                "accepted": true,
                "observed_status": "busy",
                "recovered": true,
              }
            } else {
              let response = task.create_message(
                @server.CreateMessageRequest::new(
                  message=@ai.user_message(
                    content=supervisor_worker_prompt(
                      intent,
                      request.worker_run_id,
                      retry_reason=request.reason,
                    ),
                  ),
                  web_search=intent.task.web_search,
                ),
              )
              {
                "provider_task_id": task.id.to_string(),
                "accepted": true,
                "message": response.to_json(),
              }
            }
            let receipt = match
              supervisors.worker_retry(request, provider_evidence) {
              Ok(value) => value
              Err(error) => raise supervisor_http_failure(error)
            }
            let status = match
              supervisors.worker_status(
                request.supervisor_id,
                request.worker_run_id,
              ) {
              Ok(value) => value
              Err(error) => raise supervisor_http_failure(error)
            }
            self.enforce_supervisor_worker_deadline(
              group~,
              request.supervisor_id,
              request.worker_run_id,
              status.attempt,
              intent.scope.budget.max_runtime_ms.to_int(),
            )
            receipt
          }
        }
      }
      _ =>
        raise supervisor_http_failure("unsupported supervisor worker command")
    }
  } catch {
    error =>
      raise json_error(400, "Bad Request", {
        "error": { "code": "invalid_worker_command", "message": "\{error}" },
      })
  }
  supervisor_http_json(w, 200, receipt.to_json())
}

///|
async fn Daemon::supervisor_worker_owner(
  self : Daemon,
  worker_run_id : String,
) -> String? {
  let supervisors = self.supervisor_runtime()
  for status in supervisors.list_status() {
    if status.workers.any(fn(worker) { worker.worker_run_id == worker_run_id }) {
      return Some(status.state.supervisor_id)
    }
  }
  None
}

///|
/// Restores the exact provider task UUID for every non-terminal durable worker.
/// Pending work is accepted after message delivery; running work receives one
/// recovery continuation only during daemon startup.
async fn Daemon::restore_supervisor_workers(
  self : Daemon,
  group~ : @async.TaskGroup[Unit],
) -> Unit {
  let supervisors = self.supervisor_runtime()
  for supervisor in supervisors.list_status() {
    for worker in supervisor.workers {
      if !(worker.run_status is Pending || worker.run_status is Running) {
        continue
      }
      let intent = match
        supervisors.worker_intent(
          supervisor.state.supervisor_id,
          worker.worker_run_id,
        ) {
        Ok(value) => value
        Err(error) => {
          logger.error(
            "Failed to restore durable worker intent \{worker.worker_run_id}: \{error}",
          )
          continue
        }
      }
      let task = self.ensure_supervisor_worker_task(
        group~,
        intent,
        expected_id=worker.worker_run_id,
      ) catch {
        error => {
          logger.error(
            "Failed to restore worker provider \{worker.worker_run_id}: \{error}",
          )
          continue
        }
      }
      if task.status is Busy {
        let started_at = worker.started_at.unwrap_or(
          self.clock.now().ms().to_int(),
        )
        let elapsed = (self.clock.now().ms().to_int() - started_at).max(0)
        self.enforce_supervisor_worker_deadline(
          group~,
          supervisor.state.supervisor_id,
          worker.worker_run_id,
          worker.attempt,
          (intent.scope.budget.max_runtime_ms.to_int() - elapsed).max(0),
        )
        continue
      }
      let response = task.create_message(
        @server.CreateMessageRequest::new(
          message=@ai.user_message(
            content=supervisor_worker_prompt(
              intent,
              worker.worker_run_id,
              retry_reason="daemon restart recovery",
            ),
          ),
          web_search=intent.task.web_search,
        ),
      ) catch {
        error => {
          logger.error(
            "Failed to redeliver worker provider \{worker.worker_run_id}: \{error}",
          )
          continue
        }
      }
      if worker.run_status is Pending {
        ignore(
          supervisors.record_worker_provider_acceptance(
            supervisor.state.supervisor_id,
            worker.worker_run_id,
            {
              "provider_task_id": task.id.to_string(),
              "accepted": true,
              "recovered": true,
              "accounting_mode": worker.accounting_mode,
              "message": response.to_json(),
            },
            @job.supervisor_epoch_ms_v1(self.clock.now().ms()),
          ),
        ) catch {
          error =>
            logger.error(
              "Failed to record recovered worker acceptance: \{error}",
            )
        }
      }
      let refreshed = match
        supervisors.worker_status(
          supervisor.state.supervisor_id,
          worker.worker_run_id,
        ) {
        Ok(value) => value
        Err(_) => continue
      }
      let started_at = refreshed.started_at.unwrap_or(
        self.clock.now().ms().to_int(),
      )
      let elapsed = (self.clock.now().ms().to_int() - started_at).max(0)
      self.enforce_supervisor_worker_deadline(
        group~,
        supervisor.state.supervisor_id,
        worker.worker_run_id,
        refreshed.attempt,
        (intent.scope.budget.max_runtime_ms.to_int() - elapsed).max(0),
      )
    }
  }
}
