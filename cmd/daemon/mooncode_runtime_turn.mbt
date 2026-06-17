///|
async fn Daemon::mooncode_runtime_turn(
  self : Daemon,
  session_id~ : StringView,
  r : @httpx.RequestReader,
  w : @httpx.ResponseWriter,
) -> Unit {
  let reader : @httpx.JsonRequestReader = @httpx.JsonRequestReader::new(r)
  let body : Json = reader.read() catch { _ => Json::object({}) }
  let session_id = session_id.to_string()
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
  book_root : String,
  payload : Json,
) -> Json {
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
    mooncode_append_jsonl(
      mooncode_runtime_dispatches_path(book_root, session_id),
      receipt,
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
      "claim_state": claimed_state,
      "previous_claim_state": before,
    }
  }
  let item = claimed[0]
  let command = mooncode_json_object_field_or_empty(item, "command")
  let command_id = mooncode_json_string(item, "command_id", default="")
  let scheduler_state = self.mooncode_serve_scheduler_payload(
    session_id, book_root,
  )
  let scheduler_decision = mooncode_runtime_turn_scheduler_decision(
    scheduler_state, command_id,
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
  let tool_results : Array[Json] = []
  let events : Array[Json] = [started]
  let execution : Json = if mooncode_json_bool(report, "ok", default=false) {
    let scheduler_effect = mooncode_json_string(
      scheduler_decision,
      "effect",
      default="",
    )
    if mooncode_runtime_turn_drops_idle_control(command, scheduler_effect) {
      mooncode_runtime_turn_dropped_control_execution(
        session_id,
        command_id,
        command,
        scheduler_decision,
        events,
        now=self.clock.now(),
      )
    } else {
      let mut plan = self.mooncode_runtime_turn_plan_tool_calls(
        command,
        now=self.clock.now(),
      )
      let planner_steps : Array[Json] = []
      let max_model_steps = mooncode_runtime_turn_model_max_steps(command)
      for step_index in 0..<max_model_steps {
        planner_steps.push(plan)
        for event in mooncode_json_array_items(plan, "events") {
          events.push(event)
        }
        let planned_tool_calls = mooncode_json_array_items(plan, "tool_calls")
        let tool_calls = if planned_tool_calls.length() > 0 {
          planned_tool_calls
        } else {
          mooncode_runtime_turn_tool_calls(command)
        }
        for
          event in mooncode_runtime_turn_planner_progress_events(
            session_id,
            command_id,
            plan,
            tool_calls,
            step_index~,
            now=self.clock.now(),
          ) {
          events.push(event)
        }
        let step_results : Array[Json] = []
        for tool_call in tool_calls {
          let execution = mooncode_execute_tool_call(
            session_id,
            book_root,
            mooncode_runtime_turn_tool_body(command, tool_call),
            now=self.clock.now(),
          )
          step_results.push(execution)
          tool_results.push(execution)
          events.push(mooncode_json_object_field_or_empty(execution, "event"))
          if !mooncode_json_bool(execution, "accepted", default=false) {
            break
          }
        }
        let step_accepted = step_results.all(result => {
          mooncode_json_bool(result, "accepted", default=false)
        })
        if !step_accepted ||
          mooncode_json_string(plan, "planner_mode", default="") !=
          mooncode_planner_mode_model_tool_calls() ||
          mooncode_runtime_turn_tool_calls_include_finish(tool_calls) ||
          step_index + 1 >= max_model_steps {
          break
        }
        let next_plan = self.mooncode_runtime_turn_model_followup_plan(
          command,
          plan,
          tool_calls,
          step_results,
          now=self.clock.now(),
        )
        let next_calls = mooncode_json_array_items(next_plan, "tool_calls")
        if next_calls.length() == 0 {
          planner_steps.push(next_plan)
          for event in mooncode_json_array_items(next_plan, "events") {
            events.push(event)
          }
          plan = next_plan
          break
        }
        plan = next_plan
      }
      let tool_accepted = tool_results.all(result => {
        mooncode_json_bool(result, "accepted", default=false)
      })
      let action = mooncode_json_string(command, "command", default="prompt")
      let test_results = if action == "run_tests" {
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
        events.push(test_result)
      }
      let eval_results = if tool_accepted && action == "run_eval" {
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
        events.push(eval_event)
      }
      let eval_accepted = eval_results.all(result => {
        mooncode_json_bool(result, "accepted", default=false)
      })
      let commit_results = if tool_accepted && action == "commit" {
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
        events.push(commit_event)
      }
      let commit_accepted = commit_results.all(result => {
        mooncode_json_bool(result, "accepted", default=false)
      })
      let accepted = tool_accepted && eval_accepted && commit_accepted
      if action == "steer" {
        events.push(
          mooncode_runtime_turn_steer_settlement_event(
            session_id,
            command_id,
            command,
            accepted~,
            now=self.clock.now(),
          ),
        )
      }
      let review_receipts = if accepted &&
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
        events.push(review_event)
      }
      let finished = mooncode_runtime_turn_finished_event(
        session_id,
        command_id,
        accepted~,
        tool_count=tool_results.length(),
        now=self.clock.now(),
      )
      events.push(finished)
      (
        {
          "accepted": accepted,
          "protocol": mooncode_protocol_version(),
          "session_id": session_id,
          "command_id": command_id,
          "web_search": web_search,
          "control": mooncode_json_string(command, "command", default="prompt"),
          "message": if accepted {
            "MoonClaw native runtime turn completed `\{mooncode_json_string(command, "command", default="prompt")}`"
          } else {
            "MoonClaw native runtime turn failed during tool execution"
          },
          "serve_scheduler_decision": scheduler_decision,
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
    events.push(failed)
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
  let package_results = if mooncode_json_bool(
      execution,
      "accepted",
      default=false,
    ) {
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
  let receipt = mooncode_runtime_turn_receipt(
    session_id,
    book_root,
    item,
    execution,
    consumer_id~,
    now=self.clock.now(),
  )
  mooncode_append_jsonl(
    mooncode_runtime_dispatches_path(book_root, session_id),
    receipt,
  )
  let binding = self.mooncode_binding_for_session(session_id)
  binding.book_root = book_root
  binding.command_count += 1
  binding.last_command_id = command_id
  binding.last_updated = self.clock.now()
  for event in events {
    binding.events.put(event)
    self.mooncode_persist_event(binding, event)
  }
  for index, package_result in package_results {
    binding.events.put(package_events[index])
    self.mooncode_persist_package_result(
      package_result,
      binding,
      package_events[index],
    )
  }
  self.mooncode_persist_session(binding)
  let after = self.mooncode_runtime_claim_state_payload(session_id, book_root)
  {
    "kind": mooncode_kind_runtime_turn(),
    "protocol": mooncode_protocol_version(),
    "owner": "moonclaw",
    "accepted": mooncode_json_bool(execution, "accepted", default=false),
    "session_id": session_id,
    "book_root": book_root,
    "ran": true,
    "command_id": command_id,
    "claim_receipts": Json::array(claim_receipts),
    "turn_receipt": receipt,
    "serve_scheduler_state": scheduler_state,
    "serve_scheduler_decision": scheduler_decision,
    "execution": execution,
    "package_results": Json::array(package_results),
    "package_events": Json::array(package_events),
    "claim_state": after,
    "previous_claim_state": before,
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
