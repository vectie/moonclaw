///|
fn nochange_test_policy() -> Json {
  {
    "contract": "mooncode.completion-outcome.v1",
    "allowed_outcomes": ["mutation", "no_change"],
    "no_change_reason": "already_satisfied",
    "alternative_milestone_ids": ["implementation"],
    "required_checks": [
      {
        "id": "required-tests",
        "tool": "shell",
        "command": "moon test --no-render",
        "cwd": ".",
        "exit_code": 0,
      },
    ],
    "evidence_scope": "native_tool_journal",
    "acceptance_scope": "engineering_only",
    "no_change_receipt_contract": "planbook.repair.native_no_change_receipt.v1",
  }
}

///|
fn nochange_test_command(policy? : Json = nochange_test_policy()) -> Json {
  {
    "protocol": "mooncode.v1",
    "command": "prompt",
    "session_id": "nochange-session",
    "book_root": "/synthetic/source",
    "packet": { "command_id": "nochange-command" },
    "text": "Implement the requested behavior and run tests.",
    "payload": {
      "task_intent": "workspace_change",
      "task_contract": { "completion_policy": policy },
    },
  }
}

///|
fn nochange_test_proposal() -> Json {
  {
    "reason": "already_satisfied",
    "observation": "The inspected implementation already contains the requested behavior.",
    "evidence_refs": ["nochange-read", "nochange-tests"],
  }
}

///|
fn nochange_test_result(
  tool : String,
  id : String,
  arguments : Json,
  metadata : Json,
) -> Json {
  let result : Json = { "ok": true, "is_error": false, "metadata": metadata }
  {
    "tool": tool,
    "accepted": true,
    "arguments": arguments,
    "result": result,
    "event": mooncode_json_object_with_field(
      mooncode_tool_result_event(
        "nochange-session",
        "/synthetic/source",
        "nochange-command",
        tool,
        result,
        now=@clock.Timestamp::from_ms(100L),
      ),
      "id",
      id.to_json(),
    ),
  }
}

///|
fn nochange_test_evidence() -> Array[Json] {
  [
    nochange_test_result("read", "nochange-read", { "path": "src/main.mbt" }, {
      "path": "src/main.mbt",
    }),
    nochange_test_result(
      "shell",
      "nochange-tests",
      {
        "cmd": "moon test --no-render",
        "cwd": ".",
        "verification_kind": "test",
      },
      {
        "cmd": "moon test --no-render",
        "cwd": ".",
        "exit_code": 0,
        "run_id": "run-tests",
        "approval_id": "approval-tests",
        "execution_sandbox_policy": "grant-bound",
        "sandbox_evidence": {
          "command_digest": "digest-tests",
          "cleanup_verified": true,
          "assurance": "degraded",
          "changes": [],
        },
      },
    ),
  ]
}

///|
fn nochange_test_checkpoint_arguments() -> Json {
  let milestones = mooncode_horizon_test_milestones("done", "done", "done")
  milestones[1] = mooncode_json_object_with_field(
    milestones[1],
    "resolution",
    "already_satisfied",
  )
  {
    "horizon_id": "nochange-command",
    "milestones": milestones,
    "next_action": "",
    "completion_outcome": "no_change",
    "no_change": nochange_test_proposal(),
  }
}

///|
fn nochange_test_checkpoint(
  command : Json,
  evidence : Array[Json],
  arguments? : Json = nochange_test_checkpoint_arguments(),
) -> Json {
  mooncode_runtime_horizon_checkpoint_execution(
    command,
    "nochange-session",
    "/synthetic/source",
    "nochange-command",
    { "tool": "checkpoint", "arguments": arguments },
    evidence,
    now=@clock.Timestamp::from_ms(1000L),
  )
}

///|
fn nochange_test_finish() -> Json {
  let arguments : Json = {
    "answer": "No net source change; required checks passed.",
    "completion_outcome": "no_change",
    "no_change": nochange_test_proposal(),
  }
  let result = mooncode_tool_finish(arguments)
  {
    "tool": "finish",
    "accepted": true,
    "arguments": arguments,
    "result": result,
  }
}

///|
test "nochange explicit policy accepts matching final checkpoint and checks" {
  let command = nochange_test_command()
  let evidence = nochange_test_evidence()
  let checkpoint = nochange_test_checkpoint(command, evidence)
  assert_true(
    mooncode_json_bool(checkpoint, "accepted", default=false),
    msg=checkpoint.stringify(),
  )
  let results = evidence + [checkpoint, nochange_test_finish()]
  let verdict = mooncode_runtime_turn_completion_verdict(
    command,
    results,
    require_horizon=true,
  )
  assert_true(verdict.accepted, msg=verdict.reason)
}

///|
test "nochange missing policy preserves strict legacy mutation requirement" {
  let legacy = nochange_test_command(policy=Json::null())
  let evidence = nochange_test_evidence()
  assert_false(
    mooncode_runtime_turn_completion_verdict(
      legacy,
      evidence + [nochange_test_finish()],
    ).accepted,
  )
  let plain_finish : Json = { "tool": "finish", "accepted": true }
  let verdict = mooncode_runtime_turn_completion_verdict(
    legacy,
    evidence + [plain_finish],
  )
  assert_eq(
    mooncode_runtime_turn_completion_verdict_json(verdict).stringify(),
    "{\"kind\":\"mooncode-coding-completion-verdict\",\"accepted\":false,\"reason\":\"coding completion has no accepted mutation evidence\"}",
  )
}

///|
fn nochange_test_metadata(result : Json, key : String, value : Json) -> Json {
  let payload = mooncode_runtime_turn_result_payload(result)
  let metadata = mooncode_json_object_with_field(
    mooncode_json_object_field_or_empty(payload, "metadata"),
    key,
    value,
  )
  let payload = mooncode_json_object_with_field(payload, "metadata", metadata)
  let event = mooncode_json_object_with_field(
    mooncode_json_object_field_or_empty(result, "event"),
    "tool_result",
    payload,
  )
  mooncode_json_object_with_field(
    mooncode_json_object_with_field(result, "result", payload),
    "event",
    event,
  )
}

///|
test "nochange policy is immutable versioned and retained without other contract fields" {
  let command = nochange_test_command()
  assert_eq(mooncode_nochange_policy_error(command), "")
  assert_true(
    mooncode_json_bool(
      mooncode_validate_command_body("nochange-session", command),
      "ok",
      default=false,
    ),
  )
  assert_eq(
    mooncode_nochange_field(
      mooncode_runtime_horizon_contract(command),
      "completion_policy",
    ),
    nochange_test_policy(),
  )
  assert_eq(
    mooncode_nochange_field(
      mooncode_runtime_horizon_checkpoint_contract(command),
      "completion_policy",
    ),
    nochange_test_policy(),
  )
  for
    (key, value) in [
      ("contract", "mooncode.completion-outcome.v99".to_json()),
      ("allowed_outcomes", (["no_change"] : Array[String]).to_json()),
      ("acceptance_scope", "customer_accepted".to_json()),
      ("required_checks", Json::array([])),
      ("alternative_milestone_ids", (["tests"] : Array[String]).to_json()),
      (
        "alternative_milestone_ids",
        (["implementation", "implementation"] : Array[String]).to_json(),
      ),
    ] {
    let invalid = nochange_test_command(
      policy=mooncode_json_object_with_field(nochange_test_policy(), key, value),
    )
    assert_true(mooncode_nochange_policy_error(invalid) != "", msg=key)
    assert_false(
      mooncode_json_bool(
        mooncode_validate_command_body("nochange-session", invalid),
        "ok",
        default=true,
      ),
    )
  }
  assert_eq(
    mooncode_json_string(
      mooncode_capabilities_payload(),
      "completion_outcome_contract",
      default="",
    ),
    "mooncode.completion-outcome.v1",
  )
}

///|
test "nochange requires exact commands cwd tool exit and supported actual assurance" {
  let command = nochange_test_command()
  let evidence = nochange_test_evidence()
  assert_eq(
    mooncode_nochange_proposal_error(
      command,
      nochange_test_checkpoint_arguments(),
      evidence,
    ),
    "",
  )
  for
    (key, value) in [
      ("cmd", "moon test".to_json()),
      ("cwd", "other-package".to_json()),
      ("exit_code", (1).to_json()),
      ("run_id", "".to_json()),
      ("approval_id", "".to_json()),
      ("pipeline_exit_ambiguous", true.to_json()),
      (
        "sandbox_evidence",
        ({ "cleanup_verified": false, "command_digest": "digest-tests" } : Json),
      ),
    ] {
    let bad = nochange_test_metadata(evidence[1], key, value)
    assert_true(
      mooncode_nochange_proposal_error(
        command,
        nochange_test_checkpoint_arguments(),
        [evidence[0], bad],
      ) !=
      "",
      msg=key,
    )
  }
  let absolute = nochange_test_metadata(evidence[1], "cwd", "/synthetic/source")
  assert_eq(
    mooncode_nochange_proposal_error(
      command,
      nochange_test_checkpoint_arguments(),
      [evidence[0], absolute],
    ),
    "",
  )
  let wrong_tool = mooncode_json_object_with_field(
    evidence[1],
    "tool",
    "moon_cmd",
  )
  assert_true(
    mooncode_nochange_proposal_error(
      command,
      nochange_test_checkpoint_arguments(),
      [evidence[0], wrong_tool],
    ) !=
    "",
  )
}

///|
test "nochange preserves every frozen task-specific check" {
  let extra : Json = {
    "id": "task-specific",
    "tool": "shell",
    "command": "./verify-original-task",
    "cwd": ".",
    "exit_code": 0,
  }
  let checks = mooncode_json_array_items(
      nochange_test_policy(),
      "required_checks",
    ) +
    [extra]
  let policy = mooncode_json_object_with_field(
    nochange_test_policy(),
    "required_checks",
    Json::array(checks),
  )
  let command = nochange_test_command(policy~)
  assert_true(
    mooncode_nochange_proposal_error(
      command,
      nochange_test_checkpoint_arguments(),
      nochange_test_evidence(),
    ).contains("required checks"),
  )
  assert_false(
    mooncode_json_bool(
      nochange_test_checkpoint(command, nochange_test_evidence()),
      "accepted",
      default=true,
    ),
  )
}

///|
test "nochange policy-only extension cannot discard original direct milestones" {
  let original : Json = {
    "objective": "Keep the exact original deliverable",
    "milestones": [
      {
        "id": "original-file",
        "title": "Required source file",
        "evidence_kind": "path_changed",
        "path": "src/original.mbt",
        "context_paths": [],
      },
    ],
  }
  let command = mooncode_json_object_with_field(
    nochange_test_command(),
    "task_contract",
    original,
  )
  assert_eq(
    mooncode_json_array_items(
      mooncode_runtime_horizon_task_contract(command),
      "milestones",
    ),
    mooncode_json_array_items(original, "milestones"),
  )
  assert_true(
    mooncode_nochange_policy_error(command).contains(
      "original mutation/path_changed",
    ),
  )
}

///|
test "nochange observation and references cannot be fabricated or inferred from prose" {
  let command = nochange_test_command()
  let evidence = nochange_test_evidence()
  for
    (key, value) in [
      ("reason", "".to_json()),
      ("observation", "   ".to_json()),
      ("evidence_refs", Json::array([])),
      ("evidence_refs", (["fabricated"] : Array[String]).to_json()),
      ("evidence_refs", (["nochange-read"] : Array[String]).to_json()),
      (
        "evidence_refs",
        (["nochange-tests", "nochange-tests"] : Array[String]).to_json(),
      ),
    ] {
    let proposal = mooncode_json_object_with_field(
      nochange_test_checkpoint_arguments(),
      "no_change",
      mooncode_json_object_with_field(nochange_test_proposal(), key, value),
    )
    assert_true(
      mooncode_nochange_proposal_error(command, proposal, evidence) != "",
      msg=key,
    )
  }
  let ordinary : Json = {
    "tool": "finish",
    "accepted": true,
    "arguments": { "answer": "no_change: already satisfied" },
  }
  assert_false(
    mooncode_runtime_turn_completion_verdict(command, evidence + [ordinary]).accepted,
  )
  let unknown = mooncode_json_object_with_field(
    nochange_test_checkpoint_arguments(),
    "completion_outcome",
    "success_anyway",
  )
  assert_true(
    mooncode_nochange_proposal_error(command, unknown, evidence) != "",
  )
  let wrong_type = mooncode_json_object_with_field(
    nochange_test_checkpoint_arguments(),
    "completion_outcome",
    (42).to_json(),
  )
  assert_true(
    mooncode_nochange_proposal_error(command, wrong_type, evidence) != "",
  )
  let duplicate = evidence + [evidence[1]]
  assert_true(
    mooncode_nochange_proposal_error(
      command,
      nochange_test_checkpoint_arguments(),
      duplicate,
    ) !=
    "",
  )
  let false_metadata = mooncode_json_object_with_field(
    nochange_test_finish(),
    "result",
    { "metadata": { "answer": "no_change" } },
  )
  assert_false(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [nochange_test_checkpoint(command, evidence), false_metadata],
    ).accepted,
  )
}

///|
test "nochange only named milestones can use already-satisfied alternatives" {
  let command = nochange_test_command()
  let evidence = nochange_test_evidence()
  let without_resolution = mooncode_horizon_test_milestones(
    "done", "done", "done",
  )
  let proposal = mooncode_json_object_with_field(
    nochange_test_checkpoint_arguments(),
    "milestones",
    Json::array(without_resolution),
  )
  assert_true(
    mooncode_runtime_horizon_checkpoint_error(command, proposal, evidence).contains(
      "cannot waive",
    ),
  )
  let no_alternatives = nochange_test_command(
    policy=mooncode_json_object_with_field(
      nochange_test_policy(),
      "alternative_milestone_ids",
      Json::array([]),
    ),
  )
  assert_true(
    mooncode_runtime_horizon_checkpoint_error(
      no_alternatives,
      nochange_test_checkpoint_arguments(),
      evidence,
    ).contains("not permitted"),
  )
  let changed = mooncode_json_array_items(
    nochange_test_checkpoint_arguments(),
    "milestones",
  )
  changed[1] = mooncode_json_object_with_field(
    changed[1],
    "evidence_kind",
    "scope",
  )
  assert_true(
    mooncode_runtime_horizon_checkpoint_error(
      command,
      mooncode_json_object_with_field(
        nochange_test_checkpoint_arguments(),
        "milestones",
        Json::array(changed),
      ),
      evidence,
    ).contains("changed the evidence contract"),
  )
  let wrong = mooncode_json_array_items(
    nochange_test_checkpoint_arguments(),
    "milestones",
  )
  wrong[2] = mooncode_json_object_with_field(
    wrong[2],
    "resolution",
    "already_satisfied",
  )
  assert_true(
    mooncode_runtime_horizon_checkpoint_error(
      command,
      mooncode_json_object_with_field(
        nochange_test_checkpoint_arguments(),
        "milestones",
        Json::array(wrong),
      ),
      evidence,
    ).contains("not permitted"),
  )
}

///|
fn nochange_test_edit(before : String, after : String) -> Json {
  {
    "tool": "edit",
    "accepted": true,
    "result": {
      "metadata": {
        "changed": true,
        "path": "src/main.mbt",
        "before_fingerprint": before,
        "after_fingerprint": after,
      },
    },
  }
}

///|
test "nochange edit-and-restore needs final checks and never counts as legacy mutation" {
  let command = nochange_test_command()
  let evidence = nochange_test_evidence()
  let edit = nochange_test_edit("present:before", "present:after")
  let restore = nochange_test_edit("present:after", "present:before")
  let stale = evidence + [edit, restore]
  assert_true(
    mooncode_nochange_proposal_error(
      command,
      nochange_test_checkpoint_arguments(),
      stale,
    ).contains("stale required checks"),
  )
  let net = [evidence[0], edit, evidence[1]]
  assert_true(
    mooncode_nochange_proposal_error(
      command,
      nochange_test_checkpoint_arguments(),
      net,
    ).contains("net native mutation"),
  )
  let restored = [evidence[0], edit, restore, evidence[1]]
  let checkpoint = nochange_test_checkpoint(command, restored)
  assert_true(
    mooncode_json_bool(checkpoint, "accepted", default=false),
    msg=checkpoint.stringify(),
  )
  assert_true(
    mooncode_runtime_turn_completion_verdict(
      command,
      restored + [checkpoint, nochange_test_finish()],
    ).accepted,
  )
  assert_false(
    mooncode_runtime_turn_completion_verdict(
      nochange_test_command(policy=Json::null()),
      restored + [{ "tool": "finish", "accepted": true }],
    ).accepted,
  )
}

///|
test "nochange failed required process invalidates earlier success and requires recovery" {
  let command = nochange_test_command()
  let evidence = nochange_test_evidence()
  let failed = mooncode_json_object_with_field(evidence[1], "accepted", false)
  assert_true(
    mooncode_nochange_proposal_error(
      command,
      nochange_test_checkpoint_arguments(),
      evidence + [failed],
    ).contains("required checks"),
  )
  // Even a process accepted under a nonzero expected exit cannot leave an
  // older zero-exit proof current for this exact required command.
  let nonzero = nochange_test_metadata(evidence[1], "exit_code", (1).to_json())
  assert_eq(
    mooncode_nochange_check_evidence(command, evidence + [nonzero]).length(),
    0,
  )
  let other_tool = nochange_test_result(
    "moon_cmd",
    "later-nonzero",
    { "command": "test" },
    { "command": "moon test --no-render", "cwd": ".", "exit_code": 1 },
  )
  assert_eq(
    mooncode_nochange_check_evidence(command, evidence + [other_tool]).length(),
    0,
  )
  let recovered = [evidence[0], failed, evidence[1]]
  assert_eq(
    mooncode_nochange_proposal_error(
      command,
      nochange_test_checkpoint_arguments(),
      recovered,
    ),
    "",
  )
}

///|
test "nochange requires matching fresh final checkpoint and finish" {
  let command = nochange_test_command()
  let evidence = nochange_test_evidence()
  let checkpoint = nochange_test_checkpoint(command, evidence)
  assert_false(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [nochange_test_finish()],
    ).accepted,
  )
  let different = mooncode_json_object_with_field(
    nochange_test_proposal(),
    "observation",
    "different claim",
  )
  let arguments = mooncode_json_object_with_field(
    mooncode_json_object_field_or_empty(nochange_test_finish(), "arguments"),
    "no_change",
    different,
  )
  let finish : Json = {
    "tool": "finish",
    "accepted": true,
    "arguments": arguments,
    "result": mooncode_tool_finish(arguments),
  }
  assert_false(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [checkpoint, finish],
    ).accepted,
  )
  let ordinary : Json = { "tool": "finish", "accepted": true }
  assert_false(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [checkpoint, ordinary],
    ).accepted,
  )
  let late : Json = { "tool": "moon_check", "accepted": true }
  assert_false(
    mooncode_runtime_turn_completion_verdict(
      command,
      evidence + [checkpoint, late, nochange_test_finish()],
    ).accepted,
  )
}

///|
test "nochange opt-in does not change ordinary successful mutation completion" {
  let command = nochange_test_command()
  let results : Array[Json] = [
    nochange_test_edit("present:old", "present:new"),
    nochange_test_evidence()[1],
    { "tool": "finish", "accepted": true },
  ]
  let verdict = mooncode_runtime_turn_completion_verdict(command, results)
  let legacy = mooncode_runtime_turn_completion_verdict(
    nochange_test_command(policy=Json::null()),
    results,
  )
  assert_true(verdict.accepted)
  assert_eq(
    mooncode_runtime_turn_completion_verdict_json(verdict).stringify(),
    mooncode_runtime_turn_completion_verdict_json(legacy).stringify(),
  )
  assert_eq(
    mooncode_nochange_verdict_projection(verdict, command, results),
    mooncode_runtime_turn_completion_verdict_json(legacy),
  )
}

///|
test "nochange proposal schemas preserve answer and independent goal semantics" {
  for active in [true, false] {
    let schema = mooncode_nochange_parameter_schema(
      mooncode_runtime_turn_model_finish_parameters(active),
      enabled=true,
    )
    let properties = mooncode_json_object_field_or_empty(schema, "properties")
    assert_true(
      mooncode_nochange_field(properties, "completion_outcome") != Json::null(),
    )
    assert_true(
      mooncode_nochange_field(properties, "no_change") != Json::null(),
    )
    assert_eq(mooncode_json_array_string_items(schema, "required"), ["answer"])
  }
  let legacy = mooncode_runtime_turn_model_tools_for_command(
      nochange_test_command(policy=Json::null()),
    )
    .to_json()
    .stringify()
  assert_false(legacy.contains("completion_outcome"))
  assert_false(legacy.contains("already_satisfied"))
  let opted = mooncode_runtime_turn_model_tools_for_command(
      nochange_test_command(),
    )
    .to_json()
    .stringify()
  assert_true(opted.contains("completion_outcome"))
  assert_true(opted.contains("already_satisfied"))
  let metadata = mooncode_json_object_field_or_empty(
    mooncode_runtime_turn_result_payload(nochange_test_finish()),
    "metadata",
  )
  assert_eq(mooncode_nochange_field(metadata, "goal_runtime"), Json::null())
  assert_eq(
    mooncode_nochange_field(metadata, "no_change"),
    nochange_test_proposal(),
  )
}

///|
async test "nochange checkpoint evidence survives real journal compaction hydration and terminal projections" {
  @fsx.with_temporary_directory("mooncode-nochange-journal-XXXXXX", async fn(
    root,
  ) {
    let command = nochange_test_command()
    let session_id = "nochange-session"
    let command_id = "nochange-command"
    let evidence = nochange_test_evidence()
    let checkpoint = nochange_test_checkpoint(command, evidence)
    let results = evidence + [checkpoint]
    let plan = mooncode_json_object_with_field(
      replan_compaction_test_plan([
        { "role": "user", "content": "complete checks and checkpoint" },
      ]),
      "tool_calls",
      [
        {
          "tool": "checkpoint",
          "arguments": nochange_test_checkpoint_arguments(),
        },
      ],
    )
    let continuation = mooncode_runtime_planner_replan_continuation_event(
      session_id,
      command_id,
      plan,
      finish_rejected=false,
      [plan],
      results,
      [checkpoint],
      next_step_index=1,
      replan_count=1,
      guidance="finish with the accepted no-change proposal",
      now=@clock.Timestamp::from_ms(1001L),
    )
    assert_false(continuation.stringify().contains("\"tool_results\""))
    for result in results {
      mooncode_append_session_journal(
        root,
        session_id,
        mooncode_journal_event(),
        mooncode_json_object_field_or_empty(result, "event"),
      )
    }
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_event(),
      continuation,
    )
    let journal = mooncode_read_session_journal(root, session_id)
    let events = mooncode_journal_entries(journal, mooncode_journal_event())
    let hydrated = mooncode_runtime_continuation_for_command(events, command_id)
    assert_true(
      mooncode_runtime_planner_replan_continuation_is_active(hydrated),
    )
    let retained = mooncode_json_array_items(hydrated, "tool_results")
    assert_eq(
      Json::array(retained).stringify(),
      Json::array(results).stringify(),
    )
    let complete = retained + [nochange_test_finish()]
    let verdict = mooncode_runtime_turn_completion_verdict(
      command,
      complete,
      require_horizon=true,
    )
    assert_true(verdict.accepted, msg=verdict.reason)
    let proof = mooncode_nochange_verdict_projection(verdict, command, complete)
    assert_eq(
      mooncode_json_string(proof, "completion_outcome", default=""),
      "no_change",
    )
    assert_eq(
      mooncode_json_string(proof, "original_task_acceptance", default=""),
      "unevaluated",
    )
    assert_eq(mooncode_json_array_items(proof, "required_check_evidence"), [
      { "id": "required-tests", "event_id": "nochange-tests" },
    ])
    let execution : Json = {
      "accepted": true,
      "completion_verdict": proof,
      "tool_results": complete,
    }
    let receipt = mooncode_runtime_turn_receipt(
      session_id,
      "/synthetic/source",
      {
        "command_id": command_id,
        "command": command,
        "receipt": { "claim_id": "nochange-claim" },
      },
      execution,
      consumer_id="nochange-fixture",
      now=@clock.Timestamp::from_ms(1002L),
    )
    let compact = mooncode_runtime_turn_execution_compact(execution)
    assert_eq(
      mooncode_json_object_field_or_empty(compact, "completion_verdict"),
      proof,
    )
    let receipt_execution = mooncode_json_object_field_or_empty(
      receipt, "execution",
    )
    assert_eq(
      mooncode_json_object_field_or_empty(
        receipt_execution, "completion_verdict",
      ),
      proof,
    )
    assert_eq(mooncode_json_array_items(receipt_execution, "tool_results"), [
      nochange_test_finish(),
    ])
    assert_eq(
      mooncode_json_string(receipt, "status", default=""),
      "runtime-completed",
    )
    let terminal = mooncode_runtime_turn_finished_event(
      session_id,
      command_id,
      accepted=true,
      tool_count=complete.length(),
      completion_reason=verdict.reason,
      completion_verdict=proof,
      now=@clock.Timestamp::from_ms(1003L),
    )
    assert_eq(
      mooncode_json_object_field_or_empty(terminal, "completion_verdict"),
      proof,
    )
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_event(),
      terminal,
    )
    mooncode_append_session_journal(
      root,
      session_id,
      mooncode_journal_runtime_receipt(),
      receipt,
    )
    let reloaded = mooncode_journal_entries(
      mooncode_read_session_journal(root, session_id),
      mooncode_journal_runtime_receipt(),
    )
    assert_eq(reloaded.length(), 1)
    assert_eq(
      mooncode_json_object_field_or_empty(
        mooncode_json_object_field_or_empty(reloaded[0], "execution"),
        "completion_verdict",
      ),
      proof,
    )
    assert_false(proof.stringify().contains("achieved"))
    assert_false(proof.stringify().contains("applied_and_validated"))
  })
}

///|
async test "nochange frozen command retries keep exact bytes after policy changes" {
  @fsx.with_temporary_directory("mooncode-nochange-retry-XXXXXX", async fn(
    root,
  ) {
    let command = nochange_test_command()
    mooncode_append_session_journal(
      root,
      "nochange-session",
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": "mooncode.v1",
        "session_id": "nochange-session",
        "command_id": "nochange-command",
        "created_at": @clock.Timestamp::from_ms(1L),
        "command": command,
      },
    )
    assert_true(
      mooncode_command_retry_is_exact(
        root, "nochange-session", "nochange-command", command,
      ),
    )
    let changed = nochange_test_command(
      policy=mooncode_json_object_with_field(
        nochange_test_policy(),
        "alternative_milestone_ids",
        Json::array([]),
      ),
    )
    assert_false(
      mooncode_command_retry_is_exact(
        root, "nochange-session", "nochange-command", changed,
      ),
    )
    assert_false(
      mooncode_command_retry_is_exact(
        root,
        "nochange-session",
        "nochange-command",
        nochange_test_command(policy=Json::null()),
      ),
    )
    assert_true(
      mooncode_command_retry_is_exact(
        root, "nochange-session", "nochange-command", command,
      ),
    )
    let entries = mooncode_journal_entries(
      mooncode_read_session_journal(root, "nochange-session"),
      mooncode_journal_command(),
    )
    assert_eq(entries.length(), 1)
    assert_eq(
      mooncode_json_object_field_or_empty(entries[0], "command").stringify(),
      command.stringify(),
    )
  })
}
