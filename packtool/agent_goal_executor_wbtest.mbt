///|
fn agent_goal_test_request(root : String) -> PackToolExecutionRequest {
  {
    binding: {
      pack_id: "moonclaw",
      product_id: "moonclaw",
      tool_id: "agent.goal.execute",
      input_schema_id: "agent-goal-execution-request",
      output_schema_id: "agent-goal-execution-receipt",
      authority: WorkspaceMutation,
      idempotent: true,
      evidence_outputs: [
        ".moonsuite/products/moonclaw/agent-goal-receipts", ".moonsuite/products/moonclaw/mooncode/sessions",
      ],
      review_required: true,
    },
    config: {},
    initial_input: Some({
      "contract_id": "moonclaw.agent-goal-execution-request.v1",
      "session_id": "session-agent-goal",
      "goal_id": "goal-agent-goal",
      "workspace_root": root,
      "objective": "Produce a versioned artifact",
      "criteria": [
        { "id": "artifact", "criterion": "artifact exists with evidence" },
      ],
      "role": "mooncode",
      "profile": {},
      "config": { "planner_max_steps": 2, "max_turns": 1 },
    }),
    outputs: Map([]),
    request_id: "request-agent-goal",
    attempt_id: "attempt-agent-goal-1",
    idempotency_key: "run/work/attempt/input-digest",
    operation_ref: "moonclaw/agent.goal.execute@0.1.5",
    run_id: "run-agent-goal",
    step_id: "work-agent-goal",
    evidence_path: ".moonsuite/products/moonclaw/agent-goal-receipts/receipt.json",
    attempt: 1,
    estimated_cost_micros: 0,
  }
}

///|
async fn agent_goal_test_write_journal(root : String, achieved : Bool) -> Unit {
  let journal = @pathx.join(
    root, ".moonsuite/products/moonclaw/mooncode/sessions/session-agent-goal/journal.jsonl",
  )
  @fsx.make_directory(
    @pathx.dirname(journal).to_owned(),
    recursive=true,
    exists_ok=true,
  )
  let record : Json = if achieved {
    {
      "record_kind": "event",
      "payload": {
        "event": {
          "decision": {
            "type": "achieved",
            "evidence": [
              {
                "criterion": "artifact",
                "evidence_refs": ["artifacts/result.txt"],
              },
            ],
          },
        },
      },
    }
  } else {
    { "record_kind": "command", "payload": { "status": "queued" } }
  }
  @fsx.write_to_file(journal, record.stringify() + "\n")
}

///|
async test "agent goal adapter reuses one runtime and binds artifact evidence" {
  @fsx.with_temporary_directory("agent-goal-adapter-XXXXXX", root => {
    agent_goal_test_write_journal(root, false)
    let submitted_actions : Array[Json] = []
    let reconciled_actions : Array[Json] = []
    let cancelled_actions : Array[Json] = []
    let transport = AgentGoalRuntimeTransport::new(
      submit=action => {
        submitted_actions.push(action)
        Ok({
          "contract_id": "moonclaw.agent-goal-runtime-observation.v1",
          "execution_status": "submitted",
          "goal_outcome": "none",
          "service_id": "service-agent-goal",
          "message": "submitted",
        })
      },
      reconcile=action => {
        reconciled_actions.push(action)
        @fsx.make_directory(
          @pathx.join(root, "artifacts"),
          recursive=true,
          exists_ok=true,
        )
        @fsx.write_to_file(
          @pathx.join(root, "artifacts/result.txt"),
          "versioned artifact\n",
        )
        agent_goal_test_write_journal(root, true)
        Ok({
          "contract_id": "moonclaw.agent-goal-runtime-observation.v1",
          "execution_status": "succeeded",
          "goal_outcome": "achieved",
          "service_id": "service-agent-goal",
          "message": "achieved",
        })
      },
      cancel=action => {
        cancelled_actions.push(action)
        Ok({
          "contract_id": "moonclaw.agent-goal-runtime-observation.v1",
          "execution_status": "cancelled",
          "goal_outcome": "cancelled",
          "service_id": "service-agent-goal",
          "message": "cancelled",
        })
      },
    )
    let executor = moonclaw_agent_goal_executor(transport)
    let request = agent_goal_test_request(root)
    assert_true(request.binding.review_required)
    let submitted = (executor.run)(request).unwrap()
    assert_eq(submitted.status, "submitted")
    assert_eq(submitted_actions.length(), 1)
    guard submitted.output is Object(receipt) else {
      fail("expected agent goal receipt")
    }
    assert_eq(
      agent_goal_string(receipt, "acceptance_status"),
      "review-required",
    )
    assert_eq(agent_goal_string(receipt, "model"), "gpt-5.6-sol")
    guard submitted_actions[0] is Object(action) else {
      fail("expected normalized action")
    }
    assert_eq(agent_goal_string(action, "role"), "mooncode")
    assert_eq(
      agent_goal_string(action, "native_model_selector"),
      "codex/gpt-5.6-sol",
    )
    let reconciled = executor.reconcile.unwrap()(request).unwrap()
    assert_eq(reconciled.status, "succeeded")
    assert_eq(reconciled_actions.length(), 1)
    guard reconciled.result is Some(result) &&
      result.output is Object(final_receipt) &&
      final_receipt["artifact_evidence"] is Array(evidence) else {
      fail("expected artifact evidence")
    }
    assert_true(
      evidence.any(item => {
        guard item is Object(fields) else { false }
        agent_goal_string(fields, "ref") == "artifacts/result.txt" &&
        agent_goal_string(fields, "digest").has_prefix("sha256:")
      }),
    )
    let cancelled = executor.cancel.unwrap()(request).unwrap()
    assert_eq(cancelled.status, "cancelled")
    assert_eq(cancelled_actions.length(), 1)
  })
}

///|
test "agent goal rejects product-shaped second-runtime fields" {
  let root = "/tmp/agent-goal-invalid"
  let request = agent_goal_test_request(root)
  guard request.initial_input is Some(Object(input)) else { fail("fixture") }
  input["product_id"] = "mooncode"
  try agent_goal_normalized_action(request, "submit") catch {
    error => assert_true("\{error}".contains("unsupported field: product_id"))
  } noraise {
    _ => fail("expected product identity to be rejected")
  }
}
