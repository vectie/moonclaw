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
  w.write_header(
    if mooncode_json_bool(turn, "accepted", default=false) {
      202
    } else {
      200
    },
    reason=if mooncode_json_bool(turn, "accepted", default=false) {
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
  self.mooncode_runtime_turn_execute_under_lifecycle_gate(
    session_id, book_root, payload,
  )
}

///|
async fn Daemon::mooncode_runtime_turn_execute_under_lifecycle_gate(
  self : Daemon,
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
  let resuming_continuation = mooncode_runtime_continuation_is_active(
    continuation,
  )
  let deferred_steering = if action == "steer" || action == "cancel" {
    []
  } else {
    mooncode_runtime_turn_pending_deferred_steering(existing_events)
  }
  let steered_command = mooncode_runtime_turn_command_with_deferred_steering(
    raw_command, deferred_steering,
  )
  let command = mooncode_runtime_turn_attach_active_capability(
    book_root, session_id, steered_command,
  )
  let control_state = self.mooncode_runtime_control_payload(
    session_id, book_root,
  )
  let control_decision = mooncode_runtime_turn_control_decision(
    control_state, command_id,
  )
  let web_search = mooncode_command_web_search(command)
  let report = mooncode_validate_command_body(session_id, command)
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
    []
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
            detail="MoonClaw is asking model `\{model_name}` to choose one bounded MoonCode tool batch.",
            now=plan_now,
          ),
        )
      }
      let mut plan = if resuming_continuation {
        mooncode_json_object_field_or_empty(continuation, "plan")
      } else {
        self.mooncode_runtime_turn_plan_tool_calls(command, now=plan_now)
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
      let max_model_steps = mooncode_runtime_turn_model_max_steps(command)
      let resume_step_index = if resuming_continuation {
        mooncode_json_int(continuation, "step_index", default=0)
      } else {
        0
      }
      let resume_tool_index = if resuming_continuation {
        mooncode_json_int(continuation, "tool_index", default=0)
      } else {
        0
      }
      for step_index in resume_step_index..<max_model_steps {
        let resuming_step = resuming_continuation &&
          step_index == resume_step_index
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
          let approval_events = mooncode_journal_entries(
            mooncode_read_session_journal(book_root, session_id),
            mooncode_journal_event(),
          )
          let mut approval = mooncode_runtime_tool_approval_event_for_id(
            approval_events, approval_id,
          )
          if mooncode_runtime_tool_requires_approval(tool_call) &&
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
                  now=self.clock.now(),
                ),
              )
            }
            approval = mooncode_runtime_wait_for_tool_approval(
              book_root,
              session_id,
              approval_id,
              timeout_ms=mooncode_runtime_approval_wait_ms(command),
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
          let execution = if approval_state == "rejected" {
            mooncode_runtime_rejected_tool_execution(
              session_id, book_root, command_id, tool_call, approval,
            )
          } else {
            mooncode_execute_tool_call(
              session_id,
              book_root,
              mooncode_runtime_turn_tool_body(command, tool_call),
              now=self.clock.now(),
            )
          }
          step_results.push(execution)
          tool_results.push(execution)
          self.mooncode_runtime_turn_record_event(
            binding,
            events,
            persisted_event_ids,
            mooncode_json_object_field_or_empty(execution, "event"),
          )
          if mooncode_runtime_turn_stops_tool_batch(plan, execution) {
            break
          }
        }
        if mooncode_json_string(waiting_approval, "approval_id", default="") !=
          "" {
          break
        }
        if mooncode_json_string(plan, "planner_mode", default="") !=
          mooncode_planner_mode_model_tool_calls() ||
          mooncode_runtime_turn_tool_calls_include_finish(tool_calls) ||
          step_index + 1 >= max_model_steps {
          break
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
            detail="MoonClaw is feeding tool results back to model `\{followup_model}` for another bounded MoonCode tool batch.",
            now=followup_now,
          ),
        )
        let next_plan = self.mooncode_runtime_turn_model_followup_plan(
          command,
          plan,
          tool_calls,
          step_results,
          now=followup_now,
        )
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
      let tool_accepted = if waiting {
        true
      } else if planner_failed {
        false
      } else if used_model_planner {
        mooncode_runtime_turn_model_execution_accepted(command, tool_results)
      } else {
        tool_results.all(result => {
          mooncode_json_bool(result, "accepted", default=false)
        })
      }
      let test_results = if !waiting &&
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
      let eval_results = if !waiting && tool_accepted && action == "run_eval" {
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
      let commit_results = if !waiting && tool_accepted && action == "commit" {
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
      let accepted = if waiting {
        true
      } else {
        tool_accepted && eval_accepted && commit_accepted
      }
      if action == "steer" {
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
      let review_receipts = if !waiting &&
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
      if !waiting {
        let finished = mooncode_runtime_turn_finished_event(
          session_id,
          command_id,
          accepted~,
          tool_count=tool_results.length(),
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
          "control": if waiting {
            "await_approval"
          } else {
            mooncode_json_string(command, "command", default="prompt")
          },
          "message": if waiting {
            "MoonClaw is waiting for operator approval before continuing this turn"
          } else if accepted {
            "MoonClaw native runtime turn completed `\{mooncode_json_string(command, "command", default="prompt")}`"
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
  let package_results = if !waiting_approval &&
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
  let book_results = if waiting_approval {
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
  let receipt = if waiting_approval {
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
  if !waiting_approval {
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
    "turn_receipt": if waiting_approval {
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
) -> Bool {
  !mooncode_json_bool(execution, "accepted", default=false) &&
  mooncode_json_string(plan, "planner_mode", default="") !=
  mooncode_planner_mode_model_tool_calls()
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
    "tool": mooncode_json_string(
      tool_call,
      "tool",
      default=mooncode_json_string(tool_call, "name", default=""),
    ),
    "arguments": mooncode_json_object_field_or_empty(tool_call, "arguments"),
  }
}
