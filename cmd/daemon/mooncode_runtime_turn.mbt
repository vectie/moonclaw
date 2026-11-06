///|
async fn Daemon::mooncode_runtime_turn(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch { _ => Json::object({}) }
  let session_id = session_id.to_owned()
  let requested_book_root = mooncode_request_book_root(r)
  let book_root = if requested_book_root == "" {
    mooncode_json_string(body, "book_root", default="")
  } else {
    requested_book_root
  }
  if book_root == "" {
    raise json_error(400, "Bad Request", {
      "error": {
        "code": -1,
        "message": "MoonCode runtime turn requires book_root query or JSON field",
        "metadata": { "session_id": session_id },
      },
    })
  }
  let turn = self.mooncode_runtime_turn_execute(session_id, book_root, body)
  w.header().set("Content-Type", "application/json")
  let busy = mooncode_json_string(turn, "status", default="") == "busy"
  w.write_header(
    if busy {
      409
    } else if mooncode_json_bool(turn, "accepted", default=false) {
      202
    } else {
      200
    },
    reason=if busy {
      "Conflict"
    } else if mooncode_json_bool(turn, "accepted", default=false) {
      "Accepted"
    } else {
      "OK"
    },
  )
  w.write(turn.stringify(indent=2))
}

///|
async fn Daemon::mooncode_runtime_turn_execute(
  self : Daemon,
  session_id : String,
  requested_book_root : String,
  payload : Json,
) -> Json {
  let binding = self.mooncode_binding_for_session(session_id)
  if !binding.bind_book_root(requested_book_root) {
    return {
      "kind": mooncode_kind_runtime_turn(),
      "protocol": mooncode_protocol_version(),
      "owner": "moonclaw",
      "accepted": false,
      "session_id": session_id,
      "book_root": binding.book_root,
      "requested_book_root": requested_book_root,
      "ran": false,
      "error": "MoonCode session is bound to a different MoonBook root",
    }
  }
  let book_root = binding.book_root
  let lifecycle_gate = mooncode_open_session_lifecycle_gate(
    book_root, session_id,
  )
  defer lifecycle_gate.close()
  lifecycle_gate.lock(Shared)
  defer lifecycle_gate.unlock()
  mooncode_require_active_session_state_locked(
    book_root,
    session_id,
    allow_create=true,
  )
  let execution_lease = mooncode_open_session_execution_lease(
    book_root, session_id,
  )
  defer execution_lease.close()
  if !execution_lease.try_lock(Exclusive) {
    return {
      "kind": mooncode_kind_runtime_turn(),
      "protocol": mooncode_protocol_version(),
      "owner": "moonclaw",
      "accepted": false,
      "session_id": session_id,
      "book_root": book_root,
      "ran": false,
      "status": "busy",
      "error_code": "runtime-execution-busy",
      "message": "Another MoonCode runtime owns this session's execution lease.",
    }
  }
  defer execution_lease.unlock()
  self.mooncode_runtime_turn_execute_under_runtime_gates(
    session_id, book_root, payload,
  )
}

///|
async fn Daemon::mooncode_runtime_turn_execute_under_runtime_gates(
  self : Daemon,
  group? : @async.TaskGroup[Unit],
  session_id : String,
  book_root : String,
  payload : Json,
) -> Json {
  let binding = self.mooncode_binding_for_session(session_id)
  let consumer_id = mooncode_json_string(
    payload,
    "consumer_id",
    default="moonclaw-native-runtime-turn",
  )
  // Claim selection shares the journal lock with pending cancellation, so a
  // withdrawn command cannot be resurrected by a stale pre-claim snapshot.
  let claim = mooncode_runtime_claim_atomic(
    book_root,
    session_id,
    payload,
    self.clock.now(),
  )
  let before = claim.before
  let claim_receipts = claim.receipts
  let claimed_state = self.mooncode_runtime_claim_state_payload(
    session_id, book_root,
  )
  let claimed = mooncode_json_array_items(claimed_state, "claimed_commands")
  if claimed.length() == 0 {
    return {
      "kind": mooncode_kind_runtime_turn(),
      "protocol": mooncode_protocol_version(),
      "owner": "moonclaw",
      "accepted": false,
      "session_id": session_id,
      "book_root": book_root,
      "ran": false,
      "message": "No claimable or claimed MoonCode command is ready for a native runtime turn.",
      "claim_receipts": Json::array(claim_receipts),
      "claim_state": mooncode_runtime_claim_state_compact(claimed_state),
      "previous_claim_state": mooncode_runtime_claim_state_compact(before),
    }
  }
  let item = claimed[0]
  let raw_command = mooncode_json_object_field_or_empty(item, "command")
  let command_id = mooncode_json_string(item, "command_id", default="")
  binding.runtime.active_command_id = command_id
  defer (if binding.runtime.active_command_id == command_id {
    binding.runtime.active_command_id = ""
  })
  let action = mooncode_json_string(raw_command, "command", default="prompt")
  let existing_events = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
  let continuation = mooncode_runtime_continuation_for_command(
    existing_events, command_id,
  )
  let resume_point = mooncode_runtime_resume_point(continuation)
  let resuming_continuation = resume_point is Some(_)
  let execution_started = existing_events.any(event => {
    mooncode_json_string(event, "command_id", default="") == command_id &&
    (
      (
        mooncode_json_string(event, "source", default="") ==
        "moonclaw-native-runtime-continuation" &&
        mooncode_json_string(event, "operation_state", default="") == "started"
      ) ||
      (
        mooncode_json_string(event, "source", default="") ==
        "moonclaw-native-tool-exec" &&
        mooncode_json_string(event, "event", default="") == "tool_result"
      )
    )
  })
  if claim_receipts.is_empty() && !resuming_continuation && execution_started {
    raise InvalidJournal(
      "MoonCode runtime-claimed command \{command_id} has no valid active continuation",
    )
  }
  let resuming_tools = resume_point is Some(ResumeTools(_))
  if mooncode_json_string(continuation, "command_id", default="") != "" &&
    !resuming_continuation {
    raise InvalidJournal(
      "MoonCode runtime continuation for command \{command_id} is malformed",
    )
  }
  let deferred_steering = if action == "steer" || action == "cancel" {
    []
  } else {
    mooncode_runtime_turn_pending_deferred_steering(existing_events)
  }
  let steered_command = mooncode_runtime_turn_command_with_deferred_steering(
    raw_command, deferred_steering,
  )
  let horizon_command = mooncode_runtime_horizon_attach_checkpoint(
    steered_command, existing_events,
  )
  let command = mooncode_runtime_turn_attach_active_capability(
    book_root, session_id, horizon_command,
  )
  let report = mooncode_validate_command_body(session_id, command)
  let command = mooncode_task_attach_context(book_root, session_id, command)
  let command = mooncode_json_object_with_field(
    command,
    "personal_memory",
    Json(mooncode_personal_memory_read(self.home)),
  )
  let mut command = mooncode_attach_book_instructions(book_root, command)
  for event in existing_events {
    if mooncode_json_string(event, "kind", default="") ==
      mooncode_event_steer_applied() &&
      mooncode_json_string(event, "applied_to_command_id", default="") ==
      command_id {
      command = mooncode_runtime_task_with_update(command, event)
    }
  }
  let control_state = self.mooncode_runtime_control_payload(
    session_id, book_root,
  )
  let control_decision = mooncode_runtime_turn_control_decision(
    control_state, command_id,
  )
  let web_search = mooncode_command_web_search(command)
  let now = self.clock.now()
  let started = mooncode_event(
    session_id~,
    command_id~,
    lane="runtime",
    kind="runtime.turn_started",
    title="MoonCode native runtime turn started",
    status="running",
    detail="MoonClaw claimed command \{command_id} for book-local native tool execution.",
    now~,
  )
  let tool_results : Array[Json] = if resuming_continuation {
    mooncode_json_array_items(continuation, "tool_results")
  } else {
    mooncode_runtime_horizon_retained_evidence(command)
  }
  let events : Array[Json] = []
  let persisted_event_ids : Map[String, Bool] = Map([])
  let mut waiting_approval = Json::object({})
  if !resuming_continuation {
    self.mooncode_runtime_turn_record_event(
      binding, events, persisted_event_ids, started,
    )
  }
  let execution : Json = if mooncode_json_bool(report, "ok", default=false) {
    let control_effect = mooncode_json_string(
      control_decision,
      "effect",
      default="",
    )
    if mooncode_runtime_turn_drops_idle_control(command, control_effect) {
      mooncode_runtime_turn_dropped_control_execution(
        session_id,
        command_id,
        command,
        control_decision,
        events,
        now=self.clock.now(),
      )
    } else if mooncode_runtime_turn_defers_idle_steer(command, control_effect) {
      mooncode_runtime_turn_deferred_steer_execution(
        session_id,
        command_id,
        command,
        control_decision,
        events,
        now=self.clock.now(),
      )
    } else {
      for deferred in deferred_steering {
        self.mooncode_runtime_turn_record_event(
          binding,
          events,
          persisted_event_ids,
          mooncode_runtime_turn_applied_deferred_steer_event(
            session_id,
            command_id,
            deferred,
            now=self.clock.now(),
          ),
        )
      }
      let plan_now = self.clock.now()
      if !resuming_continuation &&
        mooncode_runtime_turn_requires_model_planning(command) {
        let model_name = mooncode_runtime_turn_requested_model_label(command)
        self.mooncode_runtime_turn_record_event(
          binding,
          events,
          persisted_event_ids,
          mooncode_event(
            session_id~,
            command_id~,
            lane="runtime",
            kind="runtime.planner_started",
            title="MoonCode model planner started",
            status="running",
            detail="MoonClaw is asking model `\{model_name}` to choose one MoonCode tool batch for this planner quantum.",
            now=plan_now,
          ),
        )
      }
      let max_model_steps = mooncode_runtime_turn_model_max_steps(command)
      let applied_live_steering : Array[Json] = []
      let initial_live_steering : Array[Json] = []
      let (
        retained_transport_steering,
        retained_replan_guidance,
        retained_replan_count,
      ) = match resume_point {
        Some(ResumeTransport(_, _)) =>
          (
            mooncode_json_array_items(continuation, "pending_live_steering"),
            "",
            0,
          )
        Some(ResumeReplan(_)) =>
          (
            [],
            mooncode_json_string(
              continuation,
              "patient_replan_guidance",
              default="",
            ),
            mooncode_json_int(continuation, "replan_count", default=0),
          )
        _ => ([], "", 0)
      }
      let mut plan = match resume_point {
        Some(ResumeTools(_)) =>
          mooncode_json_object_field_or_empty(continuation, "plan")
        None | Some(ResumeTransport(true, _)) =>
          self.mooncode_runtime_turn_plan_tool_calls(
            command,
            live_steering=retained_transport_steering,
            remaining_steps=max_model_steps,
            now=plan_now,
          )
        Some(_) => {
          let previous_plan = mooncode_json_object_field_or_empty(
            continuation, "plan",
          )
          self.mooncode_runtime_turn_model_followup_plan(
            command,
            previous_plan,
            mooncode_json_array_items(previous_plan, "tool_calls"),
            mooncode_json_array_items(continuation, "step_results"),
            mooncode_json_array_items(continuation, "tool_results"),
            live_steering=retained_transport_steering,
            patient_replan_guidance=retained_replan_guidance,
            remaining_steps=max_model_steps,
            now=plan_now,
          )
        }
      }
      if !resuming_continuation &&
        mooncode_runtime_turn_requires_model_planning(command) {
        for ;; {
          let arrived_during_planning = self.mooncode_runtime_turn_claim_live_steering(
            session_id, book_root, command_id,
          )
          if arrived_during_planning.length() == 0 {
            break
          }
          command = self.mooncode_runtime_turn_apply_live_steering(
            binding, command, arrived_during_planning, applied_live_steering, events,
            persisted_event_ids,
          )
          initial_live_steering.append(arrived_during_planning)
          plan = self.mooncode_runtime_turn_plan_tool_calls(
            command,
            live_steering=initial_live_steering,
            remaining_steps=max_model_steps,
            now=self.clock.now(),
          )
        }
      }
      if mooncode_runtime_turn_model_planning_allowed(command) &&
        mooncode_runtime_turn_explicit_tool_calls(command).length() == 0 &&
        mooncode_json_string(plan, "planner_mode", default="") !=
        mooncode_planner_mode_model_tool_calls() {
        plan = mooncode_runtime_turn_failed_planner_result(
          command,
          mooncode_runtime_turn_requested_model(command),
          "model turn rejected a non-model planner projection",
          mooncode_event(
            session_id~,
            command_id~,
            lane="runtime",
            kind="runtime.planner_started",
            title="MoonCode model planner boundary",
            status="running",
            detail="MoonClaw is enforcing model-tool-calls for the selected provider model.",
            now=plan_now,
          ),
          now=plan_now,
        )
      }
      let planner_steps : Array[Json] = if resuming_continuation {
        mooncode_json_array_items(continuation, "planner_steps")
      } else {
        []
      }
      let (
        resume_step_index,
        resume_tool_index,
        stored_planner_turn_end,
        resume_approval,
      ) = match resume_point {
        Some(ResumeTools(position)) =>
          (
            position.step_index,
            position.tool_index,
            position.turn_end_step,
            position.approval,
          )
        Some(ResumePlanner(step))
        | Some(ResumeTransport(_, step))
        | Some(ResumeReplan(step)) => (step, 0, 0, None)
        None => (0, 0, 0, None)
      }
      let planner_turn_end_step = if resuming_tools &&
        stored_planner_turn_end > resume_step_index {
        stored_planner_turn_end
      } else if max_model_steps > 0 {
        resume_step_index + max_model_steps
      } else {
        0
      }
      let mut planner_pause_reason = ""
      let mut next_step_index = 0
      for step_index = resume_step_index
          planner_turn_end_step == 0 || step_index < planner_turn_end_step
          step_index = step_index + 1 {
        let resuming_step = resuming_tools && step_index == resume_step_index
        if step_index == resume_step_index &&
          mooncode_runtime_planner_pause_event(
            session_id,
            command_id,
            plan,
            mooncode_json_object_field_or_empty(continuation, "plan"),
            planner_steps,
            tool_results,
            mooncode_json_array_items(continuation, "step_results"),
            if initial_live_steering.length() > 0 {
              initial_live_steering
            } else {
              retained_transport_steering
            },
            next_step_index=step_index,
            replan_count=retained_replan_count,
            now=self.clock.now(),
          )
          is Some((checkpoint, reason)) {
          for event in mooncode_json_array_items(plan, "events") {
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, event,
            )
          }
          self.mooncode_runtime_turn_record_event(
            binding, events, persisted_event_ids, checkpoint,
          )
          planner_pause_reason = reason
          next_step_index = step_index
          break
        }
        if !resuming_step {
          planner_steps.push(plan)
          for event in mooncode_json_array_items(plan, "events") {
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, event,
            )
          }
        }
        let planned_tool_calls = mooncode_json_array_items(plan, "tool_calls")
        let planner_failed = mooncode_json_bool(plan, "failed", default=false)
        let tool_calls = if planned_tool_calls.length() > 0 {
          planned_tool_calls
        } else if planner_failed {
          []
        } else {
          mooncode_runtime_turn_tool_calls(command)
        }
        if !resuming_step {
          for
            event in mooncode_runtime_turn_planner_progress_events(
              session_id,
              command_id,
              plan,
              tool_calls,
              step_index~,
              now=self.clock.now(),
            ) {
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, event,
            )
          }
        }
        let step_results : Array[Json] = if resuming_step {
          mooncode_json_array_items(continuation, "step_results")
        } else {
          []
        }
        let parallel_read_executions = if mooncode_runtime_turn_parallel_read_batch_allowed(
            book_root,
            plan,
            tool_calls,
            resuming_step~,
          ) {
          self.mooncode_runtime_turn_execute_parallel_reads(
            command, session_id, book_root, tool_calls,
          )
        } else {
          []
        }
        let mut skill_boundary_active = false
        for tool_index, tool_call in tool_calls {
          if resuming_step && tool_index < resume_tool_index {
            continue
          }
          let tool_call = if mooncode_json_string(
              tool_call,
              "validation_error",
              default="",
            ) ==
            "" &&
            mooncode_tool_execution_arguments_error(
              mooncode_json_string(tool_call, "tool", default=""),
              mooncode_task_field(tool_call, "arguments"),
            )
            is Some(error) {
            mooncode_json_object_with_field(
              tool_call,
              "validation_error",
              Json(error),
            )
          } else {
            tool_call
          }
          let occurrence = step_index * 1000 + tool_index
          let approval_id = mooncode_runtime_tool_approval_id(
            command_id,
            tool_call,
            occurrence~,
          )
          let tool_requires_approval = mooncode_json_string(
              tool_call,
              "validation_error",
              default="",
            ) ==
            "" &&
            mooncode_runtime_tool_requires_approval(tool_call)
          let mut approval = if tool_requires_approval {
            mooncode_runtime_recent_tool_approval_event_for_id(
              book_root, session_id, approval_id,
            )
          } else {
            Json::object({})
          }
          if tool_requires_approval &&
            mooncode_json_string(approval, "state", default="pending") ==
            "pending" {
            let resuming_approval = resuming_step &&
              tool_index == resume_tool_index &&
              resume_approval is Some(_)
            let request = match resume_approval {
              Some(request) if resuming_approval => request
              _ => {
                let approval_tool_call = mooncode_runtime_bind_sandbox_approval_plan(
                    book_root, tool_call,
                  )
                  |> mooncode_json_object_with_field(
                    "approval_id",
                    Json(approval_id),
                  )
                mooncode_runtime_tool_approval_event(
                  session_id,
                  command_id,
                  approval_tool_call,
                  occurrence~,
                  state="pending",
                  tool_call_id=mooncode_runtime_turn_tool_call_id(
                    tool_call,
                    step=step_index + 1,
                    index=tool_index,
                  ),
                  now=self.clock.now(),
                )
              }
            }
            if !resuming_approval {
              self.mooncode_runtime_turn_record_event(
                binding, events, persisted_event_ids, request,
              )
              self.mooncode_runtime_turn_record_event(
                binding,
                events,
                persisted_event_ids,
                mooncode_runtime_continuation_event(
                  session_id,
                  command_id,
                  plan,
                  planner_steps,
                  tool_results,
                  step_results,
                  request,
                  step_index~,
                  tool_index~,
                  planner_turn_end_step~,
                  now=self.clock.now(),
                ),
              )
            }
            approval = mooncode_runtime_wait_for_tool_approval(
              book_root,
              session_id,
              approval_id,
              timeout_ms=if mooncode_json_bool(
                  payload,
                  "runtime_service",
                  default=false,
                ) {
                0
              } else {
                mooncode_runtime_approval_wait_ms(command)
              },
            )
            if mooncode_json_string(approval, "state", default="pending") ==
              "pending" {
              waiting_approval = request
              break
            }
          }
          let approval_state = mooncode_json_string(
            approval,
            "state",
            default="",
          )
          if approval_state == "approved" {
            self.mooncode_runtime_turn_record_event(
              binding,
              events,
              persisted_event_ids,
              mooncode_runtime_turn_tool_call_event(
                session_id,
                command_id,
                tool_call,
                step=step_index + 1,
                index=tool_index,
                mode=mooncode_json_string(plan, "planner_mode", default=""),
                model=mooncode_json_string(plan, "model", default=""),
                now=self.clock.now(),
              ),
            )
          }
          // For approved process capabilities, execute only the arguments
          // durably bound into the approval event. This prevents the planner's
          // in-memory call from substituting command text or argv after review.
          let tool_call = if tool_requires_approval {
            mooncode_runtime_authorized_tool_call(tool_call, approval)
          } else {
            mooncode_runtime_bind_sandbox_approval_plan(book_root, tool_call)
          }
          let validation_error = mooncode_json_string(
            tool_call,
            "validation_error",
            default="",
          )
          let operation_id = mooncode_runtime_operation_id(
            command_id, step_index, tool_index,
          )
          let checkpoint = mooncode_runtime_continuation_event(
            session_id,
            command_id,
            plan,
            planner_steps,
            tool_results,
            step_results,
            Json::object({}),
            step_index~,
            tool_index~,
            planner_turn_end_step~,
            now=self.clock.now(),
          )
          let recovered = mooncode_runtime_operation_recovery(
            existing_events,
            session_id,
            book_root,
            command_id,
            operation_id,
            tool_call,
            now=self.clock.now(),
          )
          let check_inputs = if recovered is None &&
            mooncode_runtime_turn_call_is_verification(tool_call) {
            mooncode_runtime_check_inputs(book_root, command, tool_results)
          } else {
            []
          }
          let finish_error = if mooncode_json_string(
              tool_call,
              "tool",
              default="",
            ) ==
            "finish" {
            mooncode_runtime_finish_input_error(
              book_root, command, tool_results,
            )
          } else {
            ""
          }
          let resuming_execution = resuming_step &&
            tool_index == resume_tool_index &&
            resume_point is Some(ResumeTools({ executing: true, .. }))
          if recovered is None && !resuming_execution {
            let checkpoint = if parallel_read_executions.is_empty() {
              mooncode_runtime_checkpoint_with_intent(
                checkpoint, operation_id, tool_call,
              )
            } else {
              checkpoint
            }
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, checkpoint,
            )
          }
          let execution : Json = if validation_error != "" || finish_error != "" {
            let tool = mooncode_json_string(tool_call, "tool", default="")
            let result = mooncode_tool_error_result(
              tool,
              message=if validation_error != "" {
                validation_error
              } else {
                finish_error
              },
            )
            mooncode_tool_execution(
              session_id,
              book_root,
              command_id,
              tool,
              mooncode_json_object_field_or_empty(tool_call, "arguments"),
              result,
              now=self.clock.now(),
            )
          } else if recovered is Some(execution) {
            execution
          } else if approval_state == "rejected" {
            mooncode_runtime_rejected_tool_execution(
              session_id, book_root, command_id, tool_call, approval,
            )
          } else if mooncode_json_string(tool_call, "tool", default="") ==
            "checkpoint" {
            mooncode_runtime_horizon_checkpoint_execution(
              command,
              session_id,
              book_root,
              command_id,
              tool_call,
              now=self.clock.now(),
            )
          } else if parallel_read_executions.length() == tool_calls.length() {
            parallel_read_executions[tool_index]
          } else {
            mooncode_execute_tool_call_in_runtime(
              group.map(group => (self, group)),
              session_id,
              book_root,
              mooncode_runtime_turn_tool_body(command, tool_call),
              now=self.clock.now(),
            )
          }
          let execution = if recovered is None {
            mooncode_runtime_bind_check_inputs(execution, check_inputs, command)
          } else {
            execution
          }
          let execution = mooncode_runtime_operation_finished(
            operation_id,
            tool_call,
            execution,
            step=step_index,
            index=tool_index,
          )
          step_results.push(execution)
          tool_results.push(execution)
          self.mooncode_runtime_turn_record_event(
            binding,
            events,
            persisted_event_ids,
            mooncode_json_object_field_or_empty(execution, "event"),
          )
          if mooncode_json_string(execution, "tool", default="") == "read_skill" {
            skill_boundary_active = true
          }
          let next_tool_call = if tool_index + 1 < tool_calls.length() {
            Some(tool_calls[tool_index + 1])
          } else {
            None
          }
          let stops_batch = match next_tool_call {
            Some(call) =>
              mooncode_runtime_turn_stops_tool_batch(
                plan,
                execution,
                skill_boundary_active~,
                next_tool_call=call,
              )
            None =>
              mooncode_runtime_turn_stops_tool_batch(
                plan,
                execution,
                skill_boundary_active~,
              )
          }
          if stops_batch {
            break
          }
        }
        if mooncode_json_string(waiting_approval, "approval_id", default="") !=
          "" {
          break
        }
        self.mooncode_runtime_turn_record_event(
          binding,
          events,
          persisted_event_ids,
          mooncode_runtime_continuation_event(
            session_id,
            command_id,
            plan,
            planner_steps,
            tool_results,
            step_results,
            Json::object({}),
            step_index~,
            tool_index=tool_calls.length(),
            planner_turn_end_step~,
            now=self.clock.now(),
          ),
        )
        let recover_incomplete_finish = mooncode_runtime_turn_recoverable_horizon_finish(
          command, plan, tool_calls, tool_results,
        )
        if planner_failed ||
          mooncode_json_string(plan, "planner_mode", default="") !=
          mooncode_planner_mode_model_tool_calls() ||
          (
            mooncode_runtime_turn_tool_calls_include_finish(tool_calls) &&
            !recover_incomplete_finish
          ) {
          break
        }
        if planner_turn_end_step > 0 && step_index + 1 >= planner_turn_end_step {
          next_step_index = step_index + 1
          self.mooncode_runtime_turn_record_event(
            binding,
            events,
            persisted_event_ids,
            mooncode_runtime_planner_continuation_event(
              session_id,
              command_id,
              plan,
              planner_steps,
              tool_results,
              step_results,
              next_step_index~,
              now=self.clock.now(),
            ),
          )
          planner_pause_reason = "planner-step-quantum"
          break
        }
        let boundary_steering = self.mooncode_runtime_turn_claim_live_steering(
          session_id, book_root, command_id,
        )
        command = self.mooncode_runtime_turn_apply_live_steering(
          binding, command, boundary_steering, applied_live_steering, events, persisted_event_ids,
        )
        let followup_now = self.clock.now()
        let followup_model = mooncode_json_string(plan, "model", default="")
        self.mooncode_runtime_turn_record_event(
          binding,
          events,
          persisted_event_ids,
          mooncode_event(
            session_id~,
            command_id~,
            lane="runtime",
            kind="runtime.planner_started",
            title="MoonCode model planner continued",
            status="running",
            detail="MoonClaw is feeding tool results back to model `\{followup_model}` for the next tool batch in this planner quantum.",
            now=followup_now,
          ),
        )
        let next_plan = for ;; {
          let next_plan = self.mooncode_runtime_turn_model_followup_plan(
            command,
            plan,
            tool_calls,
            step_results,
            tool_results,
            live_steering=boundary_steering,
            remaining_steps=if planner_turn_end_step == 0 {
              -1
            } else {
              planner_turn_end_step - step_index - 1
            },
            now=followup_now,
          )
          let arrived_during_planning = self.mooncode_runtime_turn_claim_live_steering(
            session_id, book_root, command_id,
          )
          if arrived_during_planning.length() == 0 {
            break next_plan
          }
          command = self.mooncode_runtime_turn_apply_live_steering(
            binding, command, arrived_during_planning, applied_live_steering, events,
            persisted_event_ids,
          )
          boundary_steering.append(arrived_during_planning)
        }
        if mooncode_runtime_planner_pause_event(
            session_id,
            command_id,
            next_plan,
            plan,
            planner_steps,
            tool_results,
            step_results,
            boundary_steering,
            next_step_index=step_index + 1,
            replan_count=retained_replan_count,
            now=self.clock.now(),
          )
          is Some((checkpoint, reason)) {
          for event in mooncode_json_array_items(next_plan, "events") {
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, event,
            )
          }
          self.mooncode_runtime_turn_record_event(
            binding, events, persisted_event_ids, checkpoint,
          )
          planner_pause_reason = reason
          next_step_index = step_index + 1
          break
        }
        let next_calls = mooncode_json_array_items(next_plan, "tool_calls")
        if next_calls.length() == 0 {
          planner_steps.push(next_plan)
          for event in mooncode_json_array_items(next_plan, "events") {
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, event,
            )
          }
          plan = next_plan
          break
        }
        plan = next_plan
      }
      let planner_failed = planner_steps.any(step => {
        mooncode_json_bool(step, "failed", default=false)
      })
      let waiting = mooncode_json_string(
          waiting_approval,
          "approval_id",
          default="",
        ) !=
        ""
      let completion_verdict = mooncode_runtime_turn_completion_verdict(
        command, tool_results,
      )
      let planner_paused = planner_pause_reason != ""
      let nonterminal = waiting || planner_paused
      let tool_accepted = if nonterminal {
        true
      } else {
        !planner_failed && completion_verdict.accepted
      }
      let test_results = if !nonterminal &&
        (action == "run_tests" || action == "run_build") {
        mooncode_runtime_turn_test_results(
          session_id,
          book_root,
          command,
          tool_results,
          now=self.clock.now(),
        )
      } else {
        []
      }
      let test_events : Array[Json] = []
      for test_result in test_results {
        test_events.push(test_result)
        self.mooncode_runtime_turn_record_event(
          binding, events, persisted_event_ids, test_result,
        )
      }
      let eval_results = if !nonterminal &&
        tool_accepted &&
        action == "run_eval" {
        mooncode_runtime_turn_eval_results(
          session_id,
          book_root,
          command,
          now=self.clock.now(),
        )
      } else {
        []
      }
      let eval_events : Array[Json] = []
      for eval_result in eval_results {
        let eval_event = mooncode_runtime_turn_eval_event(
          session_id,
          command_id,
          command,
          eval_result,
          now=self.clock.now(),
        )
        eval_events.push(eval_event)
        self.mooncode_runtime_turn_record_event(
          binding, events, persisted_event_ids, eval_event,
        )
      }
      let eval_accepted = eval_results.all(result => {
        mooncode_json_bool(result, "accepted", default=false)
      })
      let commit_results = if !nonterminal &&
        tool_accepted &&
        action == "commit" {
        mooncode_runtime_turn_commit_results(
          session_id,
          book_root,
          command,
          now=self.clock.now(),
        )
      } else {
        []
      }
      let commit_events : Array[Json] = []
      for commit_result in commit_results {
        let commit_event = mooncode_runtime_turn_commit_event(
          session_id,
          command_id,
          command,
          commit_result,
          now=self.clock.now(),
        )
        commit_events.push(commit_event)
        self.mooncode_runtime_turn_record_event(
          binding, events, persisted_event_ids, commit_event,
        )
      }
      let commit_accepted = commit_results.all(result => {
        mooncode_json_bool(result, "accepted", default=false)
      })
      let accepted = if nonterminal {
        true
      } else {
        tool_accepted && eval_accepted && commit_accepted
      }
      if !nonterminal && action == "steer" {
        self.mooncode_runtime_turn_record_event(
          binding,
          events,
          persisted_event_ids,
          mooncode_runtime_turn_steer_settlement_event(
            session_id,
            command_id,
            command,
            accepted~,
            now=self.clock.now(),
          ),
        )
      }
      let review_receipts = if !nonterminal &&
        accepted &&
        mooncode_runtime_turn_writes_review_receipt(action) {
        mooncode_runtime_turn_review_receipts(
          session_id,
          book_root,
          command,
          action~,
          now=self.clock.now(),
        )
      } else {
        []
      }
      let review_events : Array[Json] = []
      for receipt in review_receipts {
        let review_event = mooncode_runtime_turn_review_receipt_event(
          session_id,
          command_id,
          command,
          receipt,
          action~,
          now=self.clock.now(),
        )
        review_events.push(review_event)
        self.mooncode_runtime_turn_record_event(
          binding, events, persisted_event_ids, review_event,
        )
      }
      if !nonterminal {
        let finished = mooncode_runtime_turn_finished_event(
          session_id,
          command_id,
          accepted~,
          tool_count=tool_results.length(),
          completion_reason=completion_verdict.reason,
          completion_verdict=mooncode_runtime_turn_completion_verdict_json(
            completion_verdict,
          ),
          now=self.clock.now(),
        )
        self.mooncode_runtime_turn_record_event(
          binding, events, persisted_event_ids, finished,
        )
      }
      (
        {
          "accepted": accepted,
          "protocol": mooncode_protocol_version(),
          "session_id": session_id,
          "command_id": command_id,
          "web_search": web_search,
          "completed": !nonterminal,
          "paused": planner_paused,
          "pause_reason": planner_pause_reason,
          "next_step_index": next_step_index,
          "control": if waiting {
            "await_approval"
          } else if planner_paused {
            "continue"
          } else {
            mooncode_json_string(command, "command", default="prompt")
          },
          "message": if waiting {
            "MoonClaw is waiting for operator approval before continuing this turn"
          } else if planner_paused {
            if planner_pause_reason == "planner-transport-interrupted" {
              "MoonClaw retained the claimed command after a transient planner transport close; the runtime service will resume from its durable checkpoint"
            } else if planner_pause_reason == "planner-empty-followup" {
              "MoonClaw retained the claimed command because its accepted checkpoint is unfinished; the runtime service will ask the model to replan without a retry ceiling"
            } else {
              "MoonClaw paused after one model-planner quantum; the command remains claimed for durable continuation"
            }
          } else if accepted {
            "MoonClaw native runtime turn completed `\{mooncode_json_string(command, "command", default="prompt")}`"
          } else if !completion_verdict.accepted {
            completion_verdict.reason
          } else {
            "MoonClaw native runtime turn failed during tool execution"
          },
          "runtime_control_decision": control_decision,
          "planner": plan,
          "planner_steps": Json::array(planner_steps),
          "planner_mode": mooncode_json_string(
            plan,
            "planner_mode",
            default=mooncode_planner_mode_deterministic_fallback(),
          ),
          "planner_step_count": planner_steps.length(),
          "model_step_limit": max_model_steps,
          "completion_verdict": mooncode_runtime_turn_completion_verdict_json(
            completion_verdict,
          ),
          "tool_results": Json::array(tool_results),
          "test_results": Json::array(test_results),
          "test_events": Json::array(test_events),
          "eval_results": Json::array(eval_results),
          "eval_events": Json::array(eval_events),
          "commit_results": Json::array(commit_results),
          "commit_events": Json::array(commit_events),
          "review_receipts": Json::array(review_receipts),
          "review_events": Json::array(review_events),
          "deferred_steering": Json::array(deferred_steering),
          "applied_live_steering": Json::array(applied_live_steering),
          "waiting_approval": waiting,
          "approval": waiting_approval,
          "events": Json::array(events),
        } : Json)
    }
  } else {
    let failed = mooncode_event(
      session_id~,
      command_id~,
      lane="runtime",
      kind="runtime.turn_invalid",
      title="MoonCode native runtime turn rejected invalid command",
      status="failed",
      detail=mooncode_json_string(
        report,
        "message",
        default="Invalid MoonCode command",
      ),
      now=self.clock.now(),
    )
    self.mooncode_runtime_turn_record_event(
      binding, events, persisted_event_ids, failed,
    )
    (
      {
        "accepted": false,
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": command_id,
        "web_search": web_search,
        "control": "invalid",
        "message": mooncode_json_string(
          report,
          "message",
          default="Invalid MoonCode command",
        ),
        "validation": report,
        "tool_results": Json::array(tool_results),
        "events": Json::array(events),
      } : Json)
  }
  let waiting_approval = mooncode_json_bool(
    execution,
    "waiting_approval",
    default=false,
  )
  let planner_paused = mooncode_json_bool(execution, "paused", default=false)
  let nonterminal = waiting_approval || planner_paused
  let package_results = if !nonterminal &&
    mooncode_json_bool(execution, "accepted", default=false) {
    mooncode_runtime_turn_package_results(
      session_id,
      book_root,
      command,
      execution,
      now=self.clock.now(),
    )
  } else {
    []
  }
  let package_events : Array[Json] = []
  for package_result in package_results {
    let package_event = mooncode_package_result_event_record(
      session_id~,
      command_id~,
      package_result,
      now=self.clock.now(),
    )
    package_events.push(package_event)
  }
  let book_results = if nonterminal {
    []
  } else {
    mooncode_runtime_turn_book_results(
      session_id,
      book_root,
      command,
      execution,
      package_results,
      now=self.clock.now(),
    )
  }
  let receipt = if nonterminal {
    Json::object({})
  } else {
    mooncode_runtime_turn_receipt(
      session_id,
      book_root,
      item,
      execution,
      consumer_id~,
      now=self.clock.now(),
    )
  }
  if !nonterminal {
    ignore(
      mooncode_append_session_journal(
        book_root,
        session_id,
        mooncode_journal_runtime_receipt(),
        receipt,
      ),
    )
  }
  let journal = mooncode_read_session_journal(book_root, session_id)
  binding.command_count = mooncode_journal_record_count(
    journal,
    mooncode_journal_command(),
  )
  binding.last_command_id = command_id
  binding.last_updated = self.clock.now()
  for event in events {
    let event_id = mooncode_json_string(event, "id", default="")
    if event_id == "" || !persisted_event_ids.contains(event_id) {
      binding.events.put(event)
      self.mooncode_persist_event(binding, event)
      if event_id != "" {
        persisted_event_ids[event_id] = true
      }
    }
  }
  for index, package_result in package_results {
    binding.events.put(package_events[index])
    self.mooncode_persist_package_result(
      package_result,
      binding,
      package_events[index],
    )
  }
  for book_result in book_results {
    self.mooncode_persist_book_result(book_result, binding)
  }
  self.mooncode_persist_session(binding)
  let after = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  let compact_claim_receipts : Array[Json] = []
  for claim_receipt in claim_receipts {
    compact_claim_receipts.push(mooncode_runtime_receipt_compact(claim_receipt))
  }
  let compact_package_results : Array[Json] = []
  for package_result in package_results {
    compact_package_results.push(
      mooncode_runtime_package_result_compact(package_result),
    )
  }
  let compact_book_results : Array[Json] = []
  for book_result in book_results {
    compact_book_results.push(mooncode_runtime_book_result_compact(book_result))
  }
  {
    "kind": mooncode_kind_runtime_turn(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": mooncode_json_bool(execution, "accepted", default=false),
    "session_id": session_id,
    "book_root": book_root,
    "ran": true,
    "command_id": command_id,
    "capability_resolution": mooncode_json_object_field_or_empty(
      command, "active_capability",
    ),
    "claim_receipts": Json::array(compact_claim_receipts),
    "turn_receipt": if nonterminal {
      null
    } else {
      mooncode_runtime_receipt_compact(receipt)
    },
    "runtime_control_state": mooncode_runtime_control_state_compact(
      control_state,
    ),
    "runtime_control_decision": mooncode_runtime_control_decision_compact(
      control_decision,
    ),
    "execution": mooncode_runtime_turn_execution_compact(execution),
    "package_results": Json::array(compact_package_results),
    "package_events": Json::array(package_events),
    "book_results": Json::array(compact_book_results),
    "claim_state": mooncode_runtime_claim_state_compact(after),
    "previous_claim_state": mooncode_runtime_claim_state_compact(before),
  }
}

///|
fn mooncode_runtime_turn_stops_tool_batch(
  plan : Json,
  execution : Json,
  skill_boundary_active~ : Bool = false,
  next_tool_call? : Json,
) -> Bool {
  let result = mooncode_json_object_field_or_empty(execution, "result")
  let metadata = mooncode_json_object_field_or_empty(result, "metadata")
  let approval_state = mooncode_json_string(
    metadata,
    "approval_state",
    default="",
  )
  let ambiguous_failed_verification = mooncode_json_bool(
      metadata,
      "pipeline_exit_ambiguous",
      default=false,
    ) &&
    !mooncode_json_bool(result, "ok", default=false)
  if mooncode_json_string(execution, "tool", default="") == "ask_user" ||
    mooncode_json_string(execution, "tool", default="") == "finish" ||
    approval_state == "rejected" ||
    ambiguous_failed_verification {
    return true
  }
  let skill_boundary_active = skill_boundary_active ||
    mooncode_json_string(execution, "tool", default="") == "read_skill"
  if skill_boundary_active {
    if mooncode_json_string(execution, "tool", default="") == "read_skill" &&
      (
        !mooncode_json_bool(execution, "accepted", default=false) ||
        !mooncode_json_bool(result, "ok", default=false)
      ) {
      return true
    }
    match next_tool_call {
      Some(call) =>
        if !mooncode_runtime_turn_tool_call_is_safe_after_skill(call) {
          return true
        }
      None => return true
    }
  }
  !mooncode_json_bool(execution, "accepted", default=false) &&
  mooncode_json_string(plan, "planner_mode", default="") !=
  mooncode_planner_mode_model_tool_calls()
}

///|
/// Let already-planned, read-only evidence gathering share the inference that
/// loads a skill. Mutations and semantic/toolchain commands remain behind the
/// skill boundary so the model can consume the instructions before choosing
/// them.
fn mooncode_runtime_turn_tool_call_is_safe_after_skill(
  tool_call : Json,
) -> Bool {
  mooncode_runtime_tool_policy(tool_call).after_skill
}

///|
async fn Daemon::mooncode_runtime_turn_record_event(
  self : Daemon,
  binding : MoonCodeSessionBinding,
  events : Array[Json],
  persisted_event_ids : Map[String, Bool],
  event : Json,
) -> Unit {
  let event_id = mooncode_json_string(event, "id", default="")
  if event_id != "" && persisted_event_ids.contains(event_id) {
    return
  }
  events.push(event)
  binding.events.put(event)
  self.mooncode_persist_event(binding, event)
  if event_id != "" {
    persisted_event_ids[event_id] = true
  }
}

///|
fn mooncode_runtime_turn_tool_body(command : Json, tool_call : Json) -> Json {
  let command_id = mooncode_command_id(command)
  let tool = mooncode_json_string(
    tool_call,
    "tool",
    default=mooncode_json_string(tool_call, "name", default=""),
  )
  let arguments = mooncode_runtime_turn_apply_output_policy(
    command,
    tool,
    mooncode_json_object_field_or_empty(tool_call, "arguments"),
  )
  {
    "protocol": mooncode_protocol_version(),
    "session_id": mooncode_json_string(command, "session_id", default=""),
    "book_root": mooncode_book_root(command),
    "command_id": command_id,
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "task_contract": mooncode_runtime_horizon_task_contract(command),
    "tool": tool,
    "arguments": arguments,
  }
}

///|
fn mooncode_runtime_turn_call_is_verification(tool_call : Json) -> Bool {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  if tool == "moon_check" {
    return true
  }
  if tool == "moon_cmd" {
    let command = mooncode_json_string(arguments, "command", default="")
    return command == "check" || command == "test" || command == "build"
  }
  if tool != "shell" {
    return false
  }
  let kind = mooncode_json_string(arguments, "verification_kind", default="")
  @mooncode_tools.shell_verifies_kind(
    mooncode_json_string(arguments, "cmd", default=""),
    kind,
  )
}
