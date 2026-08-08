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
  let before = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  let claim_receipts = if mooncode_json_array_items(before, "claimed_commands").length() ==
    0 {
    mooncode_runtime_claim_receipts(
      session_id,
      book_root,
      before,
      payload,
      now=self.clock.now(),
    )
  } else {
    []
  }
  for receipt in claim_receipts {
    ignore(
      mooncode_append_session_journal(
        book_root,
        session_id,
        mooncode_journal_runtime_receipt(),
        receipt,
      ),
    )
  }
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
  binding.active_command_id = command_id
  defer (if binding.active_command_id == command_id {
    binding.active_command_id = ""
  })
  let action = mooncode_json_string(raw_command, "command", default="prompt")
  let existing_events = mooncode_journal_entries(
    mooncode_read_session_journal(book_root, session_id),
    mooncode_journal_event(),
  )
  let continuation = mooncode_runtime_continuation_for_command(
    existing_events, command_id,
  )
  let continuation_active = mooncode_runtime_continuation_is_active(
      continuation,
    ) ||
    mooncode_runtime_planner_continuation_is_active(continuation) ||
    mooncode_runtime_planner_transport_continuation_is_active(continuation) ||
    mooncode_runtime_planner_replan_continuation_is_active(continuation)
  if claim_receipts.is_empty() && !continuation_active {
    raise InvalidJournal(
      "MoonCode runtime-claimed command \{command_id} has no valid active continuation",
    )
  }
  mooncode_goal_runtime_reconcile_supervisor_events(
    book_root,
    session_id,
    self.clock.now().truncate_to_s(),
  )
  let resuming_approval = mooncode_runtime_continuation_is_active(continuation)
  let resuming_planner = mooncode_runtime_planner_continuation_is_active(
    continuation,
  )
  let resuming_planner_transport = mooncode_runtime_planner_transport_continuation_is_active(
    continuation,
  )
  let resuming_planner_replan = mooncode_runtime_planner_replan_continuation_is_active(
    continuation,
  )
  let resuming_continuation = resuming_approval ||
    resuming_planner ||
    resuming_planner_transport ||
    resuming_planner_replan
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
  let command = mooncode_goal_runtime_attach_context(
    book_root, session_id, command,
  )
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
  let persisted_event_ids : Map[String, Bool] = {}
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
      let retained_transport_steering = if resuming_planner_transport {
        mooncode_json_array_items(continuation, "pending_live_steering")
      } else {
        []
      }
      let retained_replan_guidance = if resuming_planner_replan {
        mooncode_json_string(
          continuation,
          "patient_replan_guidance",
          default="",
        )
      } else {
        ""
      }
      let retained_replan_count = if resuming_planner_replan {
        mooncode_json_int(continuation, "replan_count", default=0)
      } else {
        0
      }
      let mut plan = if resuming_approval {
        mooncode_json_object_field_or_empty(continuation, "plan")
      } else if resuming_planner {
        let previous_plan = mooncode_json_object_field_or_empty(
          continuation, "plan",
        )
        self.mooncode_runtime_turn_model_followup_plan(
          command,
          previous_plan,
          mooncode_json_array_items(previous_plan, "tool_calls"),
          mooncode_json_array_items(continuation, "step_results"),
          mooncode_json_array_items(continuation, "tool_results"),
          remaining_steps=max_model_steps,
          now=plan_now,
        )
      } else if resuming_planner_transport {
        let resume_mode = mooncode_json_string(
          continuation,
          "resume_mode",
          default="",
        )
        if resume_mode == "initial" {
          self.mooncode_runtime_turn_plan_tool_calls(
            command,
            live_steering=retained_transport_steering,
            remaining_steps=max_model_steps,
            now=plan_now,
          )
        } else {
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
            remaining_steps=max_model_steps,
            now=plan_now,
          )
        }
      } else if resuming_planner_replan {
        let previous_plan = mooncode_json_object_field_or_empty(
          continuation, "plan",
        )
        self.mooncode_runtime_turn_model_followup_plan(
          command,
          previous_plan,
          mooncode_json_array_items(previous_plan, "tool_calls"),
          mooncode_json_array_items(continuation, "step_results"),
          mooncode_json_array_items(continuation, "tool_results"),
          remaining_steps=max_model_steps,
          patient_replan_guidance=retained_replan_guidance,
          now=plan_now,
        )
      } else {
        self.mooncode_runtime_turn_plan_tool_calls(
          command,
          remaining_steps=max_model_steps,
          now=plan_now,
        )
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
          for steering in arrived_during_planning {
            initial_live_steering.push(steering)
            applied_live_steering.push(steering)
            self.mooncode_runtime_turn_record_event(
              binding,
              events,
              persisted_event_ids,
              mooncode_runtime_turn_applied_live_steer_event(
                session_id,
                steering,
                now=self.clock.now(),
              ),
            )
          }
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
      let resume_step_index = if resuming_approval {
        mooncode_json_int(continuation, "step_index", default=0)
      } else if resuming_planner ||
        resuming_planner_transport ||
        resuming_planner_replan {
        mooncode_json_int(continuation, "next_step_index", default=0)
      } else {
        0
      }
      let resume_tool_index = if resuming_approval {
        mooncode_json_int(continuation, "tool_index", default=0)
      } else {
        0
      }
      let stored_planner_turn_end = mooncode_json_int(
        continuation,
        "planner_turn_end_step",
        default=0,
      )
      let planner_turn_end_step = if resuming_approval &&
        stored_planner_turn_end > resume_step_index {
        stored_planner_turn_end
      } else if max_model_steps > 0 {
        resume_step_index + max_model_steps
      } else {
        0
      }
      let mut planner_paused = false
      let mut planner_pause_reason = ""
      let mut next_step_index = 0
      for step_index = resume_step_index
          planner_turn_end_step == 0 || step_index < planner_turn_end_step
          step_index = step_index + 1 {
        let resuming_step = resuming_approval && step_index == resume_step_index
        if mooncode_json_bool(plan, "transient_transport_close", default=false) {
          for event in mooncode_json_array_items(plan, "events") {
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, event,
            )
          }
          let resume_mode = if planner_steps.length() == 0 {
            "initial"
          } else {
            "followup"
          }
          let checkpoint_plan = if resume_mode == "initial" {
            Json::object({})
          } else {
            planner_steps[planner_steps.length() - 1]
          }
          let checkpoint_step_results = if resume_mode == "initial" {
            []
          } else {
            mooncode_json_array_items(continuation, "step_results")
          }
          self.mooncode_runtime_turn_record_event(
            binding,
            events,
            persisted_event_ids,
            mooncode_runtime_planner_transport_continuation_event(
              session_id,
              command_id,
              checkpoint_plan,
              planner_steps,
              tool_results,
              checkpoint_step_results,
              if initial_live_steering.length() > 0 {
                initial_live_steering
              } else {
                retained_transport_steering
              },
              resume_mode~,
              next_step_index=step_index,
              detail=mooncode_json_string(plan, "message", default=""),
              now=self.clock.now(),
            ),
          )
          planner_paused = true
          planner_pause_reason = "planner-transport-interrupted"
          next_step_index = step_index
          break
        }
        if mooncode_json_bool(plan, "patient_replan", default=false) {
          for event in mooncode_json_array_items(plan, "events") {
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, event,
            )
          }
          let guidance = mooncode_json_string(
            plan,
            "patient_replan_guidance",
            default="",
          )
          let retained_plan = mooncode_json_object_field_or_empty(
            continuation, "plan",
          )
          self.mooncode_runtime_turn_record_event(
            binding,
            events,
            persisted_event_ids,
            mooncode_runtime_planner_replan_continuation_event(
              session_id,
              command_id,
              retained_plan,
              finish_rejected=false,
              planner_steps,
              tool_results,
              mooncode_json_array_items(continuation, "step_results"),
              next_step_index=resume_step_index,
              replan_count=retained_replan_count + 1,
              guidance~,
              now=self.clock.now(),
            ),
          )
          planner_paused = true
          planner_pause_reason = "planner-empty-followup"
          next_step_index = resume_step_index
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
        let mut skill_boundary_active = false
        for tool_index, tool_call in tool_calls {
          if resuming_step && tool_index < resume_tool_index {
            continue
          }
          let occurrence = step_index * 1000 + tool_index
          let approval_id = mooncode_runtime_tool_approval_id(
            command_id,
            tool_call,
            occurrence~,
          )
          let tool_requires_approval = mooncode_runtime_tool_requires_approval(
            tool_call,
          )
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
              mooncode_json_string(continuation, "approval_id", default="") ==
              approval_id
            let stored_request = mooncode_json_object_field_or_empty(
              continuation, "approval",
            )
            let request = if resuming_approval &&
              mooncode_json_string(stored_request, "approval_id", default="") !=
              "" {
              stored_request
            } else {
              mooncode_runtime_tool_approval_event(
                session_id,
                command_id,
                tool_call,
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
          let post_commit_guard = mooncode_runtime_post_commit_guard(
            book_root, tool_call, tool_results,
          )
          let execution = if approval_state == "rejected" {
            mooncode_runtime_rejected_tool_execution(
              session_id, book_root, command_id, tool_call, approval,
            )
          } else if !mooncode_json_bool(
              post_commit_guard,
              "allowed",
              default=false,
            ) {
            mooncode_runtime_post_commit_rejected_execution(
              session_id,
              book_root,
              command_id,
              tool_call,
              post_commit_guard,
              now=self.clock.now(),
            )
          } else if mooncode_runtime_turn_comment_only_repair(
              command, tool_call,
            ) {
            mooncode_runtime_turn_comment_only_repair_execution(
              session_id,
              book_root,
              command_id,
              tool_call,
              now=self.clock.now(),
            )
          } else if mooncode_runtime_turn_repeats_failed_verification(
              tool_call, tool_results,
            ) {
            mooncode_runtime_turn_duplicate_failed_verification_execution(
              session_id,
              book_root,
              command_id,
              tool_call,
              now=self.clock.now(),
            )
          } else if mooncode_runtime_turn_discovery_saturated(
              command, tool_call, tool_results,
            ) {
            mooncode_runtime_turn_discovery_saturated_execution(
              session_id,
              book_root,
              command_id,
              tool_call,
              now=self.clock.now(),
            )
          } else if mooncode_runtime_turn_repeats_complete_read(
              tool_call,
              tool_results,
              active_model_messages=mooncode_json_array_items(
                plan, "model_messages",
              ),
            ) {
            mooncode_runtime_turn_duplicate_read_execution(
              session_id,
              book_root,
              command_id,
              tool_call,
              now=self.clock.now(),
            )
          } else if mooncode_json_string(tool_call, "tool", default="") ==
            "checkpoint" {
            mooncode_runtime_horizon_checkpoint_execution(
              command,
              session_id,
              book_root,
              command_id,
              tool_call,
              tool_results,
              now=self.clock.now(),
            )
          } else {
            let candidate = mooncode_execute_tool_call_in_runtime(
              group.map(group => (self, group)),
              session_id,
              book_root,
              mooncode_runtime_turn_tool_body(command, tool_call),
              now=self.clock.now(),
            )
            match
              mooncode_runtime_turn_duplicate_complete_observation_path(
                candidate,
                tool_results,
                active_model_messages=mooncode_json_array_items(
                  plan, "model_messages",
                ),
              ) {
              Some(path) =>
                mooncode_runtime_turn_duplicate_read_execution(
                  session_id,
                  book_root,
                  command_id,
                  tool_call,
                  path~,
                  now=self.clock.now(),
                )
              None => candidate
            }
          }
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
          planner_paused = true
          planner_pause_reason = "planner-step-quantum"
          break
        }
        let boundary_steering = self.mooncode_runtime_turn_claim_live_steering(
          session_id, book_root, command_id,
        )
        for steering in boundary_steering {
          applied_live_steering.push(steering)
          self.mooncode_runtime_turn_record_event(
            binding,
            events,
            persisted_event_ids,
            mooncode_runtime_turn_applied_live_steer_event(
              session_id,
              steering,
              now=self.clock.now(),
            ),
          )
        }
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
        let mut next_plan = self.mooncode_runtime_turn_model_followup_plan(
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
        for ;; {
          let arrived_during_planning = self.mooncode_runtime_turn_claim_live_steering(
            session_id, book_root, command_id,
          )
          if arrived_during_planning.length() == 0 {
            break
          }
          for steering in arrived_during_planning {
            boundary_steering.push(steering)
            applied_live_steering.push(steering)
            self.mooncode_runtime_turn_record_event(
              binding,
              events,
              persisted_event_ids,
              mooncode_runtime_turn_applied_live_steer_event(
                session_id,
                steering,
                now=self.clock.now(),
              ),
            )
          }
          next_plan = self.mooncode_runtime_turn_model_followup_plan(
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
        }
        if mooncode_json_bool(
            next_plan,
            "transient_transport_close",
            default=false,
          ) {
          for event in mooncode_json_array_items(next_plan, "events") {
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, event,
            )
          }
          self.mooncode_runtime_turn_record_event(
            binding,
            events,
            persisted_event_ids,
            mooncode_runtime_planner_transport_continuation_event(
              session_id,
              command_id,
              plan,
              planner_steps,
              tool_results,
              step_results,
              boundary_steering,
              resume_mode="followup",
              next_step_index=step_index + 1,
              detail=mooncode_json_string(next_plan, "message", default=""),
              now=self.clock.now(),
            ),
          )
          planner_paused = true
          planner_pause_reason = "planner-transport-interrupted"
          next_step_index = step_index + 1
          break
        }
        if mooncode_json_bool(next_plan, "patient_replan", default=false) {
          for event in mooncode_json_array_items(next_plan, "events") {
            self.mooncode_runtime_turn_record_event(
              binding, events, persisted_event_ids, event,
            )
          }
          let guidance = mooncode_json_string(
            next_plan,
            "patient_replan_guidance",
            default="",
          )
          self.mooncode_runtime_turn_record_event(
            binding,
            events,
            persisted_event_ids,
            mooncode_runtime_planner_replan_continuation_event(
              session_id,
              command_id,
              plan,
              finish_rejected=mooncode_runtime_turn_tool_calls_include_finish(
                mooncode_json_array_items(plan, "tool_calls"),
              ),
              planner_steps,
              tool_results,
              step_results,
              next_step_index=step_index + 1,
              replan_count=retained_replan_count + 1,
              guidance~,
              now=self.clock.now(),
            ),
          )
          planner_paused = true
          planner_pause_reason = "planner-empty-followup"
          next_step_index = step_index + 1
          break
        }
        next_plan = mooncode_runtime_turn_recovery_plan(next_plan, tool_results)
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
      let used_model_planner = planner_steps.any(step => {
        mooncode_json_string(step, "planner_mode", default="") ==
        mooncode_planner_mode_model_tool_calls()
      })
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
        command,
        tool_results,
        require_horizon=used_model_planner &&
          mooncode_runtime_turn_requires_verification(command),
      )
      let completion_gate_applies = mooncode_runtime_turn_completion_gate_applies(
        command, used_model_planner,
      )
      let nonterminal = waiting || planner_paused
      let tool_accepted = if nonterminal {
        true
      } else if planner_failed {
        false
      } else if completion_gate_applies {
        mooncode_runtime_turn_model_execution_accepted(
          command,
          tool_results,
          require_horizon=used_model_planner &&
            mooncode_runtime_turn_requires_verification(command),
        )
      } else {
        tool_results.all(result => {
          mooncode_json_bool(result, "accepted", default=false)
        })
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
          "pause_reason": if planner_paused {
            planner_pause_reason
          } else {
            ""
          },
          "next_step_index": if planner_paused {
            next_step_index
          } else {
            0
          },
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
          } else if completion_gate_applies && !completion_verdict.accepted {
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
  mooncode_goal_runtime_reconcile_supervisor_events(
    book_root,
    session_id,
    self.clock.now().truncate_to_s(),
  )
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
  skill_boundary_active? : Bool = false,
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
  if mooncode_json_string(execution, "tool", default="") == "finish" ||
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
  let tool = mooncode_json_string(tool_call, "tool", default="")
  match tool {
    "read" | "glob" | "grep" | "web_fetch" | "web_search" | "view_image" => true
    "shell" => {
      let arguments = mooncode_json_object_field_or_empty(
        tool_call, "arguments",
      )
      mooncode_shell_is_demonstrably_read_only(
        mooncode_json_string(arguments, "cmd", default=""),
      )
    }
    _ => false
  }
}

///|
fn mooncode_runtime_turn_execution_compact(execution : Json) -> Json {
  let planner = mooncode_json_object_field_or_empty(execution, "planner")
  {
    "accepted": mooncode_json_bool(execution, "accepted", default=false),
    "protocol": mooncode_json_string(execution, "protocol", default=""),
    "session_id": mooncode_json_string(execution, "session_id", default=""),
    "command_id": mooncode_json_string(execution, "command_id", default=""),
    "web_search": mooncode_json_bool(execution, "web_search", default=false),
    "control": mooncode_json_string(execution, "control", default=""),
    "message": mooncode_json_string(execution, "message", default=""),
    "completed": mooncode_json_bool(execution, "completed", default=true),
    "paused": mooncode_json_bool(execution, "paused", default=false),
    "pause_reason": mooncode_json_string(execution, "pause_reason", default=""),
    "next_step_index": mooncode_json_int(
      execution,
      "next_step_index",
      default=0,
    ),
    "waiting_approval": mooncode_json_bool(
      execution,
      "waiting_approval",
      default=false,
    ),
    "approval": mooncode_json_object_field_or_empty(execution, "approval"),
    "planner_mode": mooncode_json_string(execution, "planner_mode", default=""),
    "planner_step_count": mooncode_json_int(
      execution,
      "planner_step_count",
      default=0,
    ),
    "model_step_limit": mooncode_json_int(
      execution,
      "model_step_limit",
      default=0,
    ),
    "completion_verdict": mooncode_json_object_field_or_empty(
      execution, "completion_verdict",
    ),
    "planner": {
      "planner_mode": mooncode_json_string(planner, "planner_mode", default=""),
      "model": mooncode_json_string(planner, "model", default=""),
      "tool_call_count": mooncode_json_int(
        planner,
        "tool_call_count",
        default=0,
      ),
    },
    "tool_results": Json::array(
      mooncode_json_array_items(execution, "tool_results"),
    ),
    "test_results": Json::array(
      mooncode_json_array_items(execution, "test_results"),
    ),
    "eval_results": Json::array(
      mooncode_json_array_items(execution, "eval_results"),
    ),
    "commit_results": Json::array(
      mooncode_json_array_items(execution, "commit_results"),
    ),
    "review_receipts": Json::array(
      mooncode_json_array_items(execution, "review_receipts"),
    ),
    "deferred_steering": Json::array(
      mooncode_json_array_items(execution, "deferred_steering"),
    ),
    "applied_live_steering": Json::array(
      mooncode_json_array_items(execution, "applied_live_steering"),
    ),
  }
}

///|
fn mooncode_runtime_claim_state_compact(state : Json) -> Json {
  {
    "kind": mooncode_json_string(state, "kind", default=""),
    "protocol": mooncode_json_string(state, "protocol", default=""),
    "owner": mooncode_json_string(state, "owner", default=""),
    "session_id": mooncode_json_string(state, "session_id", default=""),
    "book_root": mooncode_json_string(state, "book_root", default=""),
    "command_count": mooncode_json_int(state, "command_count", default=0),
    "receipt_count": mooncode_json_int(state, "receipt_count", default=0),
    "claimable_command_count": mooncode_json_int(
      state,
      "claimable_command_count",
      default=0,
    ),
    "claimed_command_count": mooncode_json_int(
      state,
      "claimed_command_count",
      default=0,
    ),
    "delivered_command_count": mooncode_json_int(
      state,
      "delivered_command_count",
      default=0,
    ),
    "invalid_command_count": mooncode_json_int(
      state,
      "invalid_command_count",
      default=0,
    ),
    "order_blocked_command_count": mooncode_json_int(
      state,
      "order_blocked_command_count",
      default=0,
    ),
    "claim_ready": mooncode_json_bool(state, "claim_ready", default=false),
  }
}

///|
fn mooncode_runtime_receipt_compact(receipt : Json) -> Json {
  {
    "kind": mooncode_json_string(receipt, "kind", default=""),
    "protocol": mooncode_json_string(receipt, "protocol", default=""),
    "owner": mooncode_json_string(receipt, "owner", default=""),
    "session_id": mooncode_json_string(receipt, "session_id", default=""),
    "book_root": mooncode_json_string(receipt, "book_root", default=""),
    "command_id": mooncode_json_string(receipt, "command_id", default=""),
    "status": mooncode_json_string(receipt, "status", default=""),
    "runtime_mode": mooncode_json_string(receipt, "runtime_mode", default=""),
    "claim_id": mooncode_json_string(receipt, "claim_id", default=""),
    "consumer_id": mooncode_json_string(receipt, "consumer_id", default=""),
    "control": mooncode_json_string(receipt, "control", default=""),
    "message": mooncode_json_string(receipt, "message", default=""),
  }
}

///|
fn mooncode_runtime_control_state_compact(state : Json) -> Json {
  {
    "kind": mooncode_json_string(state, "kind", default=""),
    "protocol": mooncode_json_string(state, "protocol", default=""),
    "owner": mooncode_json_string(state, "owner", default=""),
    "session_id": mooncode_json_string(state, "session_id", default=""),
    "book_root": mooncode_json_string(state, "book_root", default=""),
    "command_count": mooncode_json_int(state, "command_count", default=0),
    "receipt_count": mooncode_json_int(state, "receipt_count", default=0),
    "active_turn_id": mooncode_json_string(state, "active_turn_id", default=""),
    "pending_turn_count": mooncode_json_int(
      state,
      "pending_turn_count",
      default=0,
    ),
    "decision_count": mooncode_json_int(state, "decision_count", default=0),
  }
}

///|
fn mooncode_runtime_control_decision_compact(decision : Json) -> Json {
  {
    "kind": mooncode_json_string(decision, "kind", default=""),
    "protocol": mooncode_json_string(decision, "protocol", default=""),
    "command_id": mooncode_json_string(decision, "command_id", default=""),
    "action": mooncode_json_string(decision, "action", default=""),
    "control": mooncode_json_string(decision, "control", default=""),
    "status": mooncode_json_string(decision, "status", default=""),
    "effect": mooncode_json_string(decision, "effect", default=""),
    "target_command_id": mooncode_json_string(
      decision,
      "target_command_id",
      default="",
    ),
    "target_state": mooncode_json_string(decision, "target_state", default=""),
    "detail": mooncode_json_string(decision, "detail", default=""),
  }
}

///|
fn mooncode_runtime_package_manifest_compact(manifest : Json) -> Json {
  {
    "kind": mooncode_json_string(manifest, "kind", default=""),
    "protocol": mooncode_json_string(manifest, "protocol", default=""),
    "status": mooncode_json_string(manifest, "status", default=""),
    "package_kind": mooncode_json_string(manifest, "package_kind", default=""),
    "context_path": mooncode_json_string(manifest, "context_path", default=""),
    "source_inventory_count": mooncode_json_int(
      manifest,
      "source_inventory_count",
      default=0,
    ),
    "source_present_count": mooncode_json_int(
      manifest,
      "source_present_count",
      default=0,
    ),
    "promoted_source_count": mooncode_json_int(
      manifest,
      "promoted_source_count",
      default=0,
    ),
    "source_promotion_status": mooncode_json_string(
      manifest,
      "source_promotion_status",
      default="",
    ),
    "manifest_path": mooncode_json_string(manifest, "manifest_path", default=""),
    "promoted_source_root": mooncode_json_string(
      manifest,
      "promoted_source_root",
      default="",
    ),
  }
}

///|
fn mooncode_runtime_package_result_compact(result : Json) -> Json {
  {
    "protocol": mooncode_json_string(result, "protocol", default=""),
    "session_id": mooncode_json_string(result, "session_id", default=""),
    "command_id": mooncode_json_string(result, "command_id", default=""),
    "event": mooncode_json_string(result, "event", default=""),
    "path": mooncode_json_string(result, "path", default=""),
    "detail": mooncode_json_string(result, "detail", default=""),
    "package_manifest": mooncode_runtime_package_manifest_compact(
      mooncode_json_object_field_or_empty(result, "package_manifest"),
    ),
  }
}

///|
fn mooncode_runtime_book_result_compact(result : Json) -> Json {
  let book_result = mooncode_json_object_field_or_empty(result, "book_result")
  let event = mooncode_json_object_field_or_empty(
    result, "executable_book_event",
  )
  {
    "kind": mooncode_json_string(result, "kind", default=""),
    "protocol": mooncode_json_string(result, "protocol", default=""),
    "owner": mooncode_json_string(result, "owner", default=""),
    "session_id": mooncode_json_string(result, "session_id", default=""),
    "command_id": mooncode_json_string(result, "command_id", default=""),
    "result_id": mooncode_json_string(result, "result_id", default=""),
    "result_path": mooncode_json_string(result, "result_path", default=""),
    "book_result": {
      "result_id": mooncode_json_string(book_result, "result_id", default=""),
      "summary": mooncode_json_string(book_result, "summary", default=""),
      "artifacts": Json::array(
        mooncode_json_array_items(book_result, "artifacts"),
      ),
      "requires_review": mooncode_json_bool(
        book_result,
        "requires_review",
        default=false,
      ),
      "notify_town": mooncode_json_bool(
        book_result,
        "notify_town",
        default=false,
      ),
    },
    "executable_book_event": {
      "protocol": mooncode_json_string(event, "protocol", default=""),
      "id": mooncode_json_string(event, "id", default=""),
      "book_id": mooncode_json_string(event, "book_id", default=""),
      "command_id": mooncode_json_string(event, "command_id", default=""),
      "result_id": mooncode_json_string(event, "result_id", default=""),
      "event_type": mooncode_json_string(event, "event_type", default=""),
      "accepted": mooncode_json_bool(event, "accepted", default=false),
      "requires_review": mooncode_json_bool(
        event,
        "requires_review",
        default=false,
      ),
      "notify_town": mooncode_json_bool(event, "notify_town", default=false),
    },
  }
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
  {
    "protocol": mooncode_protocol_version(),
    "session_id": mooncode_json_string(command, "session_id", default=""),
    "book_root": mooncode_book_root(command),
    "command_id": command_id,
    "command_packet": mooncode_json_object_field_or_empty(command, "packet"),
    "task_contract": mooncode_runtime_horizon_task_contract(command),
    "tool": mooncode_json_string(
      tool_call,
      "tool",
      default=mooncode_json_string(tool_call, "name", default=""),
    ),
    "arguments": mooncode_json_object_field_or_empty(tool_call, "arguments"),
  }
}

///|
fn mooncode_runtime_turn_comment_line(line : String) -> Bool {
  let trimmed = line.trim()
  trimmed == "" ||
  trimmed.has_prefix("//") ||
  trimmed.has_prefix("/*") ||
  trimmed.has_prefix("*") ||
  trimmed.has_prefix("*/")
}

///|
fn mooncode_runtime_turn_non_comment_lines(text : String) -> String {
  let lines : Array[String] = []
  for line in text.split("\n") {
    let owned = line.to_owned()
    if !mooncode_runtime_turn_comment_line(owned) {
      lines.push(owned.trim().to_owned())
    }
  }
  lines.join("\n")
}

///|
fn mooncode_runtime_turn_comment_only_edit(arguments : Json) -> Bool {
  let old_string = mooncode_json_string(arguments, "old_string", default="")
  let new_string = mooncode_json_string(arguments, "new_string", default="")
  old_string != "" &&
  old_string != new_string &&
  mooncode_runtime_turn_non_comment_lines(old_string) ==
  mooncode_runtime_turn_non_comment_lines(new_string)
}

///|
fn mooncode_runtime_turn_comment_only_patch(arguments : Json) -> Bool {
  let diff = mooncode_tool_patch_diff_text(arguments)
  if diff == "" {
    return false
  }
  let mut changed_line_seen = false
  for raw_line in diff.split("\n") {
    let line = raw_line.to_owned()
    if (line.has_prefix("+") && !line.has_prefix("+++")) ||
      (line.has_prefix("-") && !line.has_prefix("---")) {
      changed_line_seen = true
      if line.length() > 1 &&
        !mooncode_runtime_turn_comment_line(line[1:].to_owned()) {
        return false
      }
    }
  }
  changed_line_seen
}

///|
/// Coding and defect-repair turns must mutate behavior, configuration, tests,
/// or other non-comment content. Documentation-only requests remain available,
/// but a comment-only edit cannot satisfy a requested implementation repair.
fn mooncode_runtime_turn_comment_only_repair(
  command : Json,
  tool_call : Json,
) -> Bool {
  if !mooncode_runtime_turn_requires_verification(command) {
    return false
  }
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  match tool {
    "edit" => mooncode_runtime_turn_comment_only_edit(arguments)
    "apply_patch" | "revert_patch" =>
      mooncode_runtime_turn_comment_only_patch(arguments)
    _ => false
  }
}

///|
fn mooncode_runtime_turn_comment_only_repair_execution(
  session_id : String,
  book_root : String,
  command_id : String,
  tool_call : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let result = mooncode_tool_error_result(
    tool,
    message="comment-only mutation rejected: implementation and defect-repair turns require a substantive non-comment change",
    metadata={ "comment_only_repair": true },
  )
  {
    "accepted": false,
    "kind": "mooncode-tool-execution",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": tool,
    "arguments": arguments,
    "result": result,
    "event": mooncode_tool_result_event(
      session_id,
      book_root,
      command_id,
      tool,
      result,
      now~,
    ),
  }
}

///|
/// Return normalized local-file observations retained by one successful tool
/// execution. Native reads and shell analysis share this vocabulary so either
/// route can provide the evidence used by later planner turns.
fn mooncode_runtime_turn_result_file_observation(execution : Json) -> Json {
  let accepted = mooncode_json_bool(execution, "accepted", default=false)
  let result = mooncode_runtime_turn_result_payload(execution)
  if !accepted || !mooncode_json_bool(result, "ok", default=accepted) {
    return {}
  }
  let tool = mooncode_json_string(execution, "tool", default="")
  let metadata = mooncode_json_object_field_or_empty(result, "metadata")
  if tool == "shell" {
    let observation = mooncode_json_object_field_or_empty(
      metadata, "file_observation",
    )
    if mooncode_json_string(observation, "path", default="") == "" {
      return {}
    }
    return observation
  }
  if tool != "read" {
    return {}
  }
  let path = mooncode_json_string(
    metadata,
    "path",
    default=mooncode_json_string(
      mooncode_json_object_field_or_empty(execution, "arguments"),
      "path",
      default="",
    ),
  )
  if path == "" {
    return {}
  }
  {
    "path": path,
    "scope": if mooncode_json_bool(metadata, "truncated", default=false) ||
      mooncode_json_bool(metadata, "range_requested", default=false) {
      "partial"
    } else {
      "complete"
    },
    "source": "read",
  }
}

///|
fn mooncode_runtime_turn_context_mismatch_path(execution : Json) -> String {
  let tool = mooncode_json_string(execution, "tool", default="")
  if tool != "apply_patch" && tool != "edit" && tool != "write" {
    return ""
  }
  let result = mooncode_runtime_turn_result_payload(execution)
  let metadata = mooncode_json_object_field_or_empty(result, "metadata")
  if mooncode_json_bool(execution, "accepted", default=false) ||
    mooncode_json_bool(result, "ok", default=false) ||
    !mooncode_json_bool(metadata, "context_mismatch", default=false) {
    return ""
  }
  let path = mooncode_json_string(
    metadata,
    "file_path",
    default=mooncode_json_string(metadata, "path", default=""),
  )
  if path.contains("#hunk-") {
    mooncode_tool_first_split_piece(path, "#hunk-")
  } else {
    path
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
  mooncode_shell_verifies_kind(
    mooncode_json_string(arguments, "cmd", default=""),
    kind,
  )
}

///|
fn mooncode_runtime_turn_call_identity(tool_call : Json) -> String {
  mooncode_json_string(tool_call, "tool", default="") +
  ":" +
  mooncode_json_object_field_or_empty(tool_call, "arguments").stringify()
}

///|
/// A failed validation remains failed until authored source state changes. The
/// runtime therefore rejects an identical retry rather than relying on a retry
/// count. A changed command is new evidence; a real intervening mutation is a
/// new repository state.
fn mooncode_runtime_turn_repeats_failed_verification(
  tool_call : Json,
  results : Array[Json],
) -> Bool {
  if !mooncode_runtime_turn_call_is_verification(tool_call) {
    return false
  }
  let identity = mooncode_runtime_turn_call_identity(tool_call)
  let mut last_failure = -1
  for index, result in results {
    if mooncode_runtime_turn_call_identity(result) == identity &&
      !mooncode_json_bool(result, "accepted", default=false) {
      last_failure = index
    }
  }
  last_failure >= 0 &&
  !mooncode_runtime_turn_has_net_mutation(results[last_failure + 1:].to_owned())
}

///|
fn mooncode_runtime_turn_duplicate_failed_verification_execution(
  session_id : String,
  book_root : String,
  command_id : String,
  tool_call : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let result = mooncode_tool_error_result(
    tool,
    message="identical verification already failed with unchanged authored source state; inspect the failure, mutate the relevant source, or run a meaningfully different diagnostic",
    metadata={ "duplicate_failed_verification": true },
  )
  {
    "accepted": false,
    "kind": "mooncode-tool-execution",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": tool,
    "arguments": arguments,
    "result": result,
    "event": mooncode_tool_result_event(
      session_id,
      book_root,
      command_id,
      tool,
      result,
      now~,
    ),
  }
}

///|
fn mooncode_runtime_turn_call_is_broad_discovery(tool_call : Json) -> Bool {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  if tool == "read" {
    return mooncode_json_int(arguments, "start_line", default=0) <= 0 &&
      mooncode_json_int(arguments, "end_line", default=0) <= 0
  }
  if tool != "shell" || mooncode_runtime_turn_call_is_verification(tool_call) {
    return false
  }
  let command = mooncode_json_string(arguments, "cmd", default="").to_lower()
  command.contains("find ") ||
  command.contains("ls ") ||
  command.contains("rg --files") ||
  command.contains("git status") ||
  command.trim() == "pwd" ||
  command.contains("pwd &&")
}

///|
fn mooncode_runtime_turn_call_is_implementation_discovery(
  tool_call : Json,
) -> Bool {
  if mooncode_runtime_turn_call_is_broad_discovery(tool_call) {
    return true
  }
  let tool = mooncode_json_string(tool_call, "tool", default="")
  if tool == "read" || tool == "moon_ide" {
    return true
  }
  if tool != "shell" || mooncode_runtime_turn_call_is_verification(tool_call) {
    return false
  }
  let command = mooncode_json_string(
    mooncode_json_object_field_or_empty(tool_call, "arguments"),
    "cmd",
    default="",
  ).to_lower()
  command.contains("rg ") ||
  command.contains("grep ") ||
  command.contains("sed -n") ||
  command.contains("cat ") ||
  command.contains("head ") ||
  command.contains("tail ") ||
  command.contains("git diff") ||
  command.contains("git log") ||
  command.contains("stat ") ||
  command.contains("wc ")
}

///|
fn mooncode_runtime_turn_successful_discovery(execution : Json) -> Bool {
  if !mooncode_runtime_turn_call_is_implementation_discovery(execution) ||
    !mooncode_json_bool(execution, "accepted", default=false) {
    return false
  }
  let result = mooncode_runtime_turn_result_payload(execution)
  mooncode_json_bool(result, "ok", default=true)
}

///|
/// A failed content mutation invalidates the model's assumed bytes for that
/// exact file. Permit one successful reread of the same path even when the
/// general discovery allowance is exhausted; the reread consumes this escape
/// hatch because its observation is newer than the mismatch.
fn mooncode_runtime_turn_recovers_context_mismatch(
  tool_call : Json,
  results : Array[Json],
) -> Bool {
  if mooncode_json_string(tool_call, "tool", default="") != "read" {
    return false
  }
  let path = mooncode_json_string(
    mooncode_json_object_field_or_empty(tool_call, "arguments"),
    "path",
    default="",
  )
  if path == "" {
    return false
  }
  let mut last_mismatch = -1
  let mut last_successful_observation = -1
  for index, execution in results {
    if mooncode_runtime_turn_context_mismatch_path(execution) == path {
      last_mismatch = index
    }
    let observation = mooncode_runtime_turn_result_file_observation(execution)
    if mooncode_json_string(observation, "path", default="") == path &&
      mooncode_runtime_turn_successful_discovery(execution) {
      last_successful_observation = index
    }
  }
  last_mismatch >= 0 && last_successful_observation < last_mismatch
}

///|
/// Implementation requests get a real evidence pass, not an unbounded
/// inspection phase. A substantive mutation resets the allowance. After the
/// broad pass, a bounded set of exact line-range reads and targeted semantic
/// diagnostics remains available for concrete missing patch facts.
fn mooncode_runtime_turn_discovery_saturated(
  command : Json,
  tool_call : Json,
  results : Array[Json],
) -> Bool {
  if !mooncode_runtime_turn_requires_verification(command) ||
    !mooncode_runtime_turn_call_is_implementation_discovery(tool_call) {
    return false
  }
  if mooncode_runtime_turn_recovers_context_mismatch(tool_call, results) {
    return false
  }
  let mut successful_broad_discovery = 0
  let mut successful_discovery = 0
  for execution in results {
    if mooncode_runtime_turn_result_is_mutation(execution) {
      successful_broad_discovery = 0
      successful_discovery = 0
    } else if mooncode_runtime_turn_successful_discovery(execution) {
      successful_discovery += 1
      if mooncode_runtime_turn_call_is_broad_discovery(execution) {
        successful_broad_discovery += 1
      }
    }
  }
  successful_discovery >= 12 ||
  (
    mooncode_runtime_turn_call_is_broad_discovery(tool_call) &&
    successful_broad_discovery >= 6
  )
}

///|
fn mooncode_runtime_turn_discovery_saturated_execution(
  session_id : String,
  book_root : String,
  command_id : String,
  tool_call : Json,
  now~ : @clock.Timestamp,
) -> Json {
  let tool = mooncode_json_string(tool_call, "tool", default="")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let result = mooncode_tool_error_result(
    tool,
    message="implementation discovery is saturated with no authored mutation; use retained evidence to make a substantive edit, apply_patch, or write now. The runtime permits at most six broad and twelve total source-discovery observations between mutations.",
    metadata={
      "discovery_saturated": true,
      "broad_observation_limit": 6,
      "total_observation_limit": 12,
    },
  )
  {
    "accepted": false,
    "kind": "mooncode-tool-execution",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": tool,
    "arguments": arguments,
    "result": result,
    "event": mooncode_tool_result_event(
      session_id,
      book_root,
      command_id,
      tool,
      result,
      now~,
    ),
  }
}

///|
fn mooncode_runtime_turn_path_has_retained_complete_observation(
  path : String,
  results : Array[Json],
) -> Bool {
  let mut last_complete_observation = -1
  let mut last_context_mismatch = -1
  let mut last_mutation = -1
  for index, result in results {
    if mooncode_runtime_turn_result_is_mutation(result) {
      last_mutation = index
    }
    if mooncode_runtime_turn_context_mismatch_path(result) == path {
      last_context_mismatch = index
    }
    let observation = mooncode_runtime_turn_result_file_observation(result)
    if mooncode_json_string(observation, "path", default="") == path &&
      mooncode_json_string(observation, "scope", default="") == "complete" {
      last_complete_observation = index
    }
  }
  last_complete_observation >= 0 &&
  last_mutation < last_complete_observation &&
  last_context_mismatch < last_complete_observation
}

///|
/// A complete local-file observation remains valid until an accepted authored
/// mutation. A later same-path context mismatch makes exactly one complete
/// reread causal; that reread becomes the newest observation and consumes the
/// allowance without any separate counter or ledger.
fn mooncode_runtime_turn_repeats_complete_read(
  tool_call : Json,
  results : Array[Json],
  active_model_messages? : Array[Json] = [],
) -> Bool {
  if mooncode_json_string(tool_call, "tool", default="") != "read" {
    return false
  }
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  // A precise line-range read is the recovery path after transcript
  // compaction or a compiler/patch diagnostic. Only reject another unbounded
  // complete read of evidence that is already durably retained.
  if mooncode_json_int(arguments, "start_line", default=0) > 0 ||
    mooncode_json_int(arguments, "end_line", default=0) > 0 {
    return false
  }
  let path = mooncode_json_string(arguments, "path", default="")
  if path == "" {
    return false
  }
  mooncode_runtime_turn_path_has_retained_complete_observation(path, results) &&
  (
    active_model_messages.length() == 0 ||
    mooncode_runtime_turn_model_context_retains_complete_observation(
      path, active_model_messages,
    )
  )
}

///|
/// A durable result can outlive the provider transcript that exposed its file
/// bytes. Once long-run compaction removes that assistant/tool exchange, the
/// model must be allowed to read the file again. A provider-truncated tool
/// message does not retain the complete bytes even when the durable result did.
fn mooncode_runtime_turn_model_context_retains_complete_observation(
  path : String,
  messages : Array[Json],
) -> Bool {
  // Long-run transcript compaction replaces old source bytes with a current
  // cumulative evidence receipt. That receipt is sufficient to reject another
  // unbounded read while still allowing a causally targeted line-range read.
  let quoted_path = "\"" + path + "\""
  for message in messages {
    let content = mooncode_json_string(message, "content", default="")
    if content.contains("\"complete_read_paths\"") &&
      content.contains(quoted_path) {
      return true
    }
  }
  for message_index, message in messages {
    if mooncode_json_string(message, "role", default="") != "assistant" {
      continue
    }
    for call in mooncode_json_array_items(message, "tool_calls") {
      let function = mooncode_json_object_field_or_empty(call, "function")
      if mooncode_json_string(function, "name", default="") != "read" {
        continue
      }
      let arguments_text = mooncode_json_string(
        function,
        "arguments",
        default="",
      )
      let mut matching_call = false
      for
        arguments in mooncode_runtime_turn_model_argument_values(arguments_text) {
        if mooncode_json_string(arguments, "path", default="") == path {
          matching_call = true
          break
        }
      }
      if !matching_call {
        continue
      }
      let call_id = mooncode_json_string(call, "id", default="")
      if call_id == "" {
        continue
      }
      for later_index in (message_index + 1)..<messages.length() {
        let later = messages[later_index]
        if mooncode_json_string(later, "role", default="") == "tool" &&
          mooncode_json_string(later, "tool_call_id", default="") == call_id {
          return !mooncode_json_string(later, "content", default="").contains(
            "...[truncated for planner context]",
          )
        }
      }
    }
  }
  false
}

///|
/// Shell completeness is established only after successful output is captured.
/// A partial observation is never rejected, which leaves causal narrow rereads
/// available after compiler or patch failures.
fn mooncode_runtime_turn_duplicate_complete_observation_path(
  execution : Json,
  prior_results : Array[Json],
  active_model_messages? : Array[Json] = [],
) -> String? {
  if mooncode_json_string(execution, "tool", default="") != "shell" {
    return None
  }
  let observation = mooncode_runtime_turn_result_file_observation(execution)
  if mooncode_json_string(observation, "scope", default="") == "complete" {
    let path = mooncode_json_string(observation, "path", default="")
    if path != "" &&
      mooncode_runtime_turn_path_has_retained_complete_observation(
        path, prior_results,
      ) &&
      (
        active_model_messages.length() == 0 ||
        mooncode_runtime_turn_model_context_retains_complete_observation(
          path, active_model_messages,
        )
      ) {
      return Some(path)
    }
  }
  None
}

///|
fn mooncode_runtime_turn_duplicate_read_execution(
  session_id : String,
  book_root : String,
  command_id : String,
  tool_call : Json,
  path? : String = "",
  now~ : @clock.Timestamp,
) -> Json {
  let tool = mooncode_json_string(tool_call, "tool", default="read")
  let arguments = mooncode_json_object_field_or_empty(tool_call, "arguments")
  let path = if path == "" {
    mooncode_json_string(arguments, "path", default="")
  } else {
    path
  }
  let result = mooncode_tool_error_result(
    tool,
    message="duplicate complete read of `\{path}`; use the existing planner context or mutate before reading this path again",
    metadata={ "path": path, "duplicate_complete_read": true },
  )
  {
    "accepted": false,
    "kind": "mooncode-tool-execution",
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "session_id": session_id,
    "book_root": book_root,
    "command_id": command_id,
    "tool": tool,
    "arguments": arguments,
    "result": result,
    "event": mooncode_tool_result_event(
      session_id,
      book_root,
      command_id,
      tool,
      result,
      now~,
    ),
  }
}
