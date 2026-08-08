///|
fn mooncode_horizon_test_milestones(
  scope : String,
  implementation : String,
  tests : String,
) -> Array[Json] {
  [
    {
      "id": "scope",
      "title": "Locate the owned implementation surface",
      "status": scope,
      "evidence_kind": "scope",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "implementation",
      "title": "Implement the requested behavior",
      "status": implementation,
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "tests",
      "title": "Pass the requested typed tests",
      "status": tests,
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
}

///|
test "mooncode multi-file patch evidence retains every changed path" {
  let patch : Json = {
    "tool": "apply_patch",
    "accepted": true,
    "result": {
      "metadata": {
        "path": "patchset",
        "changed": true,
        "files": [
          {
            "file_path": "internal/review/moon.pkg",
            "changed": true,
            "before_fingerprint": "absent",
            "after_fingerprint": "present:package",
          },
          {
            "file_path": "internal/review/review_diff.mbt",
            "changed": true,
            "before_fingerprint": "absent",
            "after_fingerprint": "present:implementation",
          },
        ],
      },
    },
  }
  assert_true(
    mooncode_runtime_horizon_path_changed(
      [patch],
      "internal/review/review_diff.mbt",
    ),
  )
  assert_true(mooncode_runtime_horizon_path_changed([patch], "internal/review"))
  assert_false(mooncode_runtime_horizon_path_changed([patch], "internal/rev"))
  assert_true(
    mooncode_runtime_horizon_has_substantive_mutation(
      {
        "command": "prompt",
        "text": "Implement the requested review behavior.",
      },
      [patch],
    ),
  )
}

///|
test "mooncode long-horizon fallback retains build and visual validation" {
  let command : Json = {
    "command": "prompt",
    "text": "Implement the UI, run tests, build it, and UI-to-UI visually validate desktop and phone.",
  }
  let milestones = mooncode_runtime_horizon_required_milestones(command)
  assert_eq(milestones.length(), 5)
  assert_eq(
    mooncode_json_string(milestones[2], "evidence_kind", default=""),
    "test",
  )
  assert_eq(
    mooncode_json_string(milestones[3], "evidence_kind", default=""),
    "build",
  )
  assert_eq(
    mooncode_json_string(milestones[4], "evidence_kind", default=""),
    "visual",
  )
  let results : Array[Json] = [
    {
      "tool": "edit",
      "accepted": true,
      "result": {
        "metadata": {
          "path": "src/ui.mbt",
          "changed": true,
          "before_fingerprint": "present:old",
          "after_fingerprint": "present:new",
        },
      },
    },
    {
      "tool": "browser",
      "accepted": true,
      "result": { "message": "desktop and phone rendered" },
    },
  ]
  assert_true(
    mooncode_runtime_horizon_milestone_proven(command, milestones[4], results),
  )
  assert_false(
    mooncode_runtime_horizon_milestone_proven(command, milestones[4], [
      results[0],
    ]),
  )
}

///|
test "mooncode dirty continuation derives exact mutation evidence from commit" {
  let milestones : Array[Json] = [
    {
      "id": "implementation",
      "title": "Implement the repair",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "tests",
      "title": "Pass tests",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let active : Array[Json] = [
    {
      "id": "implementation",
      "title": "Implement the repair",
      "status": "active",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "tests",
      "title": "Pass tests",
      "status": "pending",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let command : Json = {
    "command": "prompt",
    "text": "Finish the implementation and run tests.",
    "payload": {
      "horizon_id": "dirty-continuation",
      "task_contract": {
        "horizon_id": "dirty-continuation",
        "objective": "Finish and validate the repair",
        "milestones": Json::array(milestones),
      },
    },
  }
  let attached = mooncode_runtime_horizon_attach_checkpoint(command, [
    {
      "tool": "checkpoint",
      "tool_result": {
        "ok": true,
        "metadata": {
          "horizon_id": "dirty-continuation",
          "checkpoint": {
            "horizon_id": "dirty-continuation",
            "milestones": Json::array(active),
            "next_action": "Commit the legitimate dirty work.",
          },
        },
      },
    },
    {
      "kind": "runtime.commit_created",
      "status": "done",
      "commit_sha": "abc123",
      "horizon_id": "dirty-continuation",
      "changed_paths": [
        "internal/review/moon.pkg", "internal/review/review_diff.mbt",
      ],
    },
  ])
  let retained = mooncode_runtime_horizon_retained_evidence(attached)
  assert_eq(retained.length(), 1)
  assert_true(mooncode_runtime_turn_result_is_mutation(retained[0]))
  let completed : Array[Json] = [
    {
      "id": "implementation",
      "title": "Implement the repair",
      "status": "done",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "tests",
      "title": "Pass tests",
      "status": "active",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  assert_eq(
    mooncode_runtime_horizon_checkpoint_error(
      attached,
      {
        "horizon_id": "dirty-continuation",
        "milestones": Json::array(completed),
        "next_action": "Run tests.",
      },
      retained,
    ),
    "",
  )
}

///|
test "mooncode retained commit evidence stays within its active horizon" {
  let checkpoint : Json = {
    "tool": "checkpoint",
    "tool_result": {
      "ok": true,
      "metadata": {
        "horizon_id": "older-horizon",
        "checkpoint": {
          "horizon_id": "older-horizon",
          "milestones": [
            {
              "id": "implementation",
              "title": "Implement",
              "status": "active",
              "evidence_kind": "mutation",
              "path": "",
              "context_paths": [],
            },
          ],
          "next_action": "Commit.",
        },
      },
    },
  }
  let commit : Json = {
    "kind": "runtime.commit_created",
    "status": "done",
    "commit_sha": "historical123",
    "horizon_id": "older-horizon",
    "changed_paths": ["src/historical.mbt"],
  }
  let fresh : Json = {
    "command": "prompt",
    "text": "Implement fresh work.",
    "payload": { "horizon_id": "fresh-horizon" },
  }
  assert_true(
    mooncode_runtime_horizon_retained_evidence(
      mooncode_runtime_horizon_attach_checkpoint(fresh, [checkpoint, commit]),
    ).is_empty(),
  )
  let older : Json = {
    "command": "prompt",
    "text": "Continue older work.",
    "payload": { "horizon_id": "older-horizon" },
  }
  let unrelated_checkpoint : Json = {
    "tool": "checkpoint",
    "tool_result": {
      "ok": true,
      "metadata": {
        "horizon_id": "other-horizon",
        "checkpoint": {
          "horizon_id": "other-horizon",
          "milestones": [
            {
              "id": "other",
              "title": "Other work",
              "status": "active",
              "evidence_kind": "mutation",
              "path": "",
              "context_paths": [],
            },
          ],
          "next_action": "Commit other work.",
        },
      },
    },
  }
  assert_true(
    mooncode_runtime_horizon_retained_evidence(
      mooncode_runtime_horizon_attach_checkpoint(older, [
        checkpoint, unrelated_checkpoint, commit,
      ]),
    ).is_empty(),
  )
  let unrelated_commit : Json = {
    "kind": "runtime.commit_created",
    "status": "done",
    "commit_sha": "later456",
    "horizon_id": "fresh-horizon",
    "changed_paths": ["src/unrelated.mbt"],
  }
  assert_true(
    mooncode_runtime_horizon_retained_evidence(
      mooncode_runtime_horizon_attach_checkpoint(older, [
        checkpoint, unrelated_commit,
      ]),
    ).is_empty(),
  )
}

///|
test "mooncode terminal matching accepts retained commit and later verification" {
  let milestones : Array[Json] = [
    {
      "id": "implementation",
      "title": "Implement the repair",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "tests",
      "title": "Pass tests",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let command : Json = {
    "command": "prompt",
    "text": "Finish the implementation and run tests.",
    "payload": {
      "horizon_id": "terminal-commit",
      "task_contract": {
        "horizon_id": "terminal-commit",
        "objective": "Finish and validate the repair",
        "milestones": Json::array(milestones),
      },
    },
  }
  let commit : Json = {
    "tool": "commit",
    "accepted": true,
    "result": {
      "metadata": {
        "evidence_kind": "runtime.commit_created",
        "commit_sha": "def456",
        "changed_paths": ["src/runtime.mbt", "src/runtime_test.mbt"],
      },
    },
  }
  let verification : Json = {
    "tool": "moon_cmd",
    "accepted": true,
    "arguments": { "command": "test" },
    "result": { "metadata": {} },
  }
  let all_done : Array[Json] = [
    {
      "id": "implementation",
      "title": "Implement the repair",
      "status": "done",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "tests",
      "title": "Pass tests",
      "status": "done",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let checkpoint : Json = {
    "tool": "checkpoint",
    "accepted": true,
    "result": {
      "metadata": {
        "horizon_id": "terminal-commit",
        "checkpoint": {
          "horizon_id": "terminal-commit",
          "milestones": Json::array(all_done),
          "next_action": "Finish.",
        },
      },
    },
  }
  let finish : Json = {
    "tool": "finish",
    "accepted": true,
    "result": { "metadata": {} },
  }
  let results = [commit, verification, checkpoint, finish]
  assert_eq(
    mooncode_runtime_horizon_checkpoint_error(
      command,
      {
        "horizon_id": "terminal-commit",
        "milestones": Json::array(all_done),
        "next_action": "Finish.",
      },
      [commit, verification],
    ),
    "",
  )
  assert_true(mooncode_runtime_horizon_completion_ready(command, results))
  assert_true(
    mooncode_runtime_turn_completion_verdict(
      command,
      results,
      require_horizon=true,
    ).accepted,
  )
}

///|
test "mooncode finish accepts an all-done checkpoint after a verified commit seal" {
  let milestones : Array[Json] = [
    {
      "id": "implementation",
      "title": "Implement the repair",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "tests",
      "title": "Pass tests",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let command : Json = {
    "command": "prompt",
    "text": "Implement the repair and run tests.",
    "payload": {
      "horizon_id": "verified-commit-finish",
      "task_contract": {
        "horizon_id": "verified-commit-finish",
        "objective": "Finish the verified repair",
        "milestones": Json::array(milestones),
      },
    },
  }
  let source_change : Json = {
    "tool": "apply_patch",
    "accepted": true,
    "result": {
      "metadata": {
        "changed": true,
        "files": [
          {
            "changed": true,
            "path": "src/runtime.mbt",
            "before_fingerprint": "before",
            "after_fingerprint": "after",
          },
        ],
      },
    },
  }
  let verification : Json = {
    "tool": "moon_cmd",
    "accepted": true,
    "arguments": { "command": "test" },
    "result": { "metadata": {} },
  }
  let commit : Json = {
    "tool": "shell",
    "accepted": true,
    "result": {
      "metadata": {
        "post_commit_boundary": true,
        "post_commit_capture_valid": true,
        "commit_sha": "ccf291e8",
        "changed_paths": ["src/runtime.mbt"],
      },
    },
  }
  let checkpoint : Json = {
    "tool": "checkpoint",
    "accepted": true,
    "result": {
      "metadata": {
        "horizon_id": "verified-commit-finish",
        "checkpoint": {
          "horizon_id": "verified-commit-finish",
          "milestones": [
            {
              "id": "implementation",
              "title": "Implement the repair",
              "status": "done",
              "evidence_kind": "mutation",
              "path": "",
              "context_paths": [],
            },
            {
              "id": "tests",
              "title": "Pass tests",
              "status": "done",
              "evidence_kind": "test",
              "path": "",
              "context_paths": [],
            },
          ],
          "next_action": "Finish without another test or mutation.",
        },
      },
    },
  }
  let finish : Json = {
    "tool": "finish",
    "accepted": true,
    "result": { "metadata": {} },
  }
  let results = [source_change, verification, commit, checkpoint, finish]
  assert_true(mooncode_runtime_horizon_completion_ready(command, results))
  let verdict = mooncode_runtime_turn_completion_verdict(
    command,
    results,
    require_horizon=true,
  )
  assert_true(verdict.accepted)
  assert_eq(
    verdict.reason,
    "coding completion has accepted mutation and subsequent successful typed test evidence",
  )
  assert_false(
    mooncode_runtime_turn_recoverable_horizon_finish(
      command,
      { "planner_mode": "model-tool-calls" },
      [{ "tool": "finish", "arguments": { "answer": "done" } }],
      results,
    ),
  )
}

///|
test "mooncode implementation milestones reject documentation-only evidence" {
  let command : Json = {
    "command": "prompt",
    "text": "Implement every missing product behavior and run tests.",
  }
  let documentation : Json = {
    "tool": "edit",
    "accepted": true,
    "result": {
      "metadata": {
        "path": "docs/STATUS.md",
        "changed": true,
        "before_fingerprint": "present:status-0",
        "after_fingerprint": "present:status-1",
      },
    },
  }
  assert_false(
    mooncode_runtime_horizon_has_substantive_mutation(command, [documentation]),
  )
  let implementation : Json = {
    "tool": "apply_patch",
    "accepted": true,
    "result": {
      "metadata": {
        "path": "src/runtime.mbt",
        "changed": true,
        "before_fingerprint": "present:runtime-0",
        "after_fingerprint": "present:runtime-1",
      },
    },
  }
  assert_true(
    mooncode_runtime_horizon_has_substantive_mutation(command, [
      documentation, implementation,
    ]),
  )
  let documentation_request : Json = {
    "command": "prompt",
    "text": "Document the current release workflow.",
  }
  assert_true(
    mooncode_runtime_horizon_has_substantive_mutation(documentation_request, [
      documentation,
    ]),
  )
}

///|
test "mooncode checkpoint explains immutable documentation evidence contract" {
  let milestones : Array[Json] = [
    {
      "id": "deliverable",
      "title": "Caller-supplied deliverable",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "verification",
      "title": "Caller-supplied verification",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let command : Json = {
    "command": "prompt",
    "text": "Implement the requested deliverable and run tests.",
    "payload": {
      "horizon_id": "immutable-documentation-contract",
      "task_contract": {
        "horizon_id": "immutable-documentation-contract",
        "objective": "Caller-supplied objective",
        "milestones": Json::array(milestones),
      },
    },
  }
  let supplied : Array[Json] = [
    {
      "id": "deliverable",
      "title": "Caller-supplied deliverable",
      "status": "done",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "verification",
      "title": "Caller-supplied verification",
      "status": "active",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let documentation : Json = {
    "tool": "edit",
    "accepted": true,
    "result": {
      "metadata": {
        "path": "docs/deliverable.md",
        "changed": true,
        "before_fingerprint": "present:documentation-0",
        "after_fingerprint": "present:documentation-1",
      },
    },
  }
  assert_eq(
    mooncode_runtime_horizon_checkpoint_error(
      command,
      {
        "horizon_id": "immutable-documentation-contract",
        "milestones": Json::array(supplied),
        "next_action": "Continue.",
      },
      [documentation],
    ),
    "checkpoint milestone `deliverable` is blocked by the immutable task contract: documentation-only changes do not satisfy evidence_kind `mutation`; a documentation deliverable must be declared as evidence_kind `path_changed` with its exact path in the initial task contract",
  )
}

///|
test "mooncode requires distinct evidence for newly completed phase milestones" {
  let milestones : Array[Json] = [
    {
      "id": "phase-2",
      "title": "Complete Phase 2",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "phase-3",
      "title": "Complete Phase 3",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
  ]
  let command : Json = {
    "command": "prompt",
    "text": "Implement Phase 2 and Phase 3, then run tests.",
    "payload": {
      "horizon_id": "phases",
      "task_contract": {
        "horizon_id": "phases",
        "objective": "Complete both phases",
        "milestones": Json::array(milestones),
      },
    },
  }
  let completed : Array[Json] = [
    {
      "id": "phase-2",
      "title": "Complete Phase 2",
      "status": "done",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "phase-3",
      "title": "Complete Phase 3",
      "status": "done",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
  ]
  let arguments : Json = {
    "horizon_id": "phases",
    "milestones": Json::array(completed),
    "next_action": "Finish.",
  }
  let phase_2 : Json = {
    "tool": "edit",
    "accepted": true,
    "result": {
      "metadata": {
        "path": ".github/workflows/ci.yml",
        "changed": true,
        "before_fingerprint": "present:ci-0",
        "after_fingerprint": "present:ci-1",
      },
    },
  }
  let insufficient = mooncode_runtime_horizon_checkpoint_error(
    command,
    arguments,
    [phase_2],
  )
  assert_true(insufficient.contains("only 1 unconsumed substantive mutation"))
  let phase_3 : Json = {
    "tool": "apply_patch",
    "accepted": true,
    "result": {
      "metadata": {
        "path": "internal/mooncode/protocol.mbt",
        "changed": true,
        "before_fingerprint": "present:protocol-0",
        "after_fingerprint": "present:protocol-1",
      },
    },
  }
  assert_eq(
    mooncode_runtime_horizon_checkpoint_error(command, arguments, [
      phase_2, phase_3,
    ]),
    "",
  )
}

///|
test "mooncode retains mutation evidence while an active milestone is validated" {
  let milestones : Array[Json] = [
    {
      "id": "repair",
      "title": "Implement and validate the repair",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "hosted",
      "title": "Observe hosted validation",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let active : Array[Json] = [
    {
      "id": "repair",
      "title": "Implement and validate the repair",
      "status": "active",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "hosted",
      "title": "Observe hosted validation",
      "status": "pending",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let completed : Array[Json] = [
    {
      "id": "repair",
      "title": "Implement and validate the repair",
      "status": "done",
      "evidence_kind": "mutation",
      "path": "",
      "context_paths": [],
    },
    {
      "id": "hosted",
      "title": "Observe hosted validation",
      "status": "active",
      "evidence_kind": "test",
      "path": "",
      "context_paths": [],
    },
  ]
  let command : Json = {
    "command": "prompt",
    "text": "Implement the repair and observe hosted validation.",
    "payload": {
      "horizon_id": "retained-mutation",
      "task_contract": {
        "horizon_id": "retained-mutation",
        "objective": "Repair and validate",
        "milestones": Json::array(milestones),
      },
    },
  }
  let mutation : Json = {
    "tool": "edit",
    "accepted": true,
    "result": {
      "metadata": {
        "path": "src/runtime.mbt",
        "changed": true,
        "before_fingerprint": "present:runtime-0",
        "after_fingerprint": "present:runtime-1",
      },
    },
  }
  let prior_checkpoint : Json = {
    "tool": "checkpoint",
    "accepted": true,
    "result": {
      "metadata": {
        "horizon_id": "retained-mutation",
        "checkpoint": {
          "horizon_id": "retained-mutation",
          "milestones": Json::array(active),
          "next_action": "Validate the repair.",
        },
      },
    },
  }
  let arguments : Json = {
    "horizon_id": "retained-mutation",
    "milestones": Json::array(completed),
    "next_action": "Observe hosted validation.",
  }
  assert_eq(
    mooncode_runtime_horizon_checkpoint_error(command, arguments, [
      mutation, prior_checkpoint,
    ]),
    "",
  )
}

///|
test "mooncode long-horizon loop compacts reference appendices and proves every milestone" {
  let mut appendix = ""
  for _ in 0..<2000 {
    appendix += "0123456789"
  }
  let command : Json = {
    "command": "prompt",
    "command_id": "command-horizon",
    "payload": { "horizon_id": "horizon-1" },
    "text": "Implement the parser repair across src/parser.mbt and src/parser_test.mbt, then run tests.\nFull authoritative plan follows:\n" +
    appendix,
  }
  let compact = mooncode_runtime_horizon_compact_request(command)
  assert_true(compact.contains("Implement the parser repair"))
  assert_true(compact.contains("Reference appendix omitted"))
  assert_false(compact.contains("0123456789"))
  assert_true(compact.length() < 1000)
  let exposed_tools = mooncode_runtime_turn_model_tools_for_command(command)
    .to_json()
    .stringify()
  assert_true(exposed_tools.contains("\"apply_patch\""))
  assert_true(exposed_tools.contains("\"checkpoint\""))

  let results : Array[Json] = [
    {
      "tool": "read",
      "accepted": true,
      "arguments": { "path": "src/parser.mbt" },
      "result": {
        "message": "read src/parser.mbt",
        "metadata": { "path": "src/parser.mbt", "truncated": false },
      },
    },
  ]
  let initial_checkpoint = mooncode_runtime_horizon_checkpoint_execution(
    command,
    "session-horizon",
    "/tmp/book",
    "command-horizon",
    {
      "tool": "checkpoint",
      "arguments": {
        "horizon_id": "horizon-1",
        "milestones": Json::array(
          mooncode_horizon_test_milestones("done", "active", "pending"),
        ),
        "next_action": "Patch the parser and its tests.",
      },
    },
    results,
    now=@clock.Timestamp::from_ms(1L),
  )
  assert_true(mooncode_json_bool(initial_checkpoint, "accepted", default=false))
  results.push(initial_checkpoint)
  results.push({
    "tool": "apply_patch",
    "accepted": true,
    "result": {
      "message": "patched parser and tests",
      "metadata": {
        "changed": true,
        "files": [
          {
            "file_path": "src/parser.mbt",
            "changed": true,
            "before_fingerprint": "present:parser-0",
            "after_fingerprint": "present:parser-1",
          },
          {
            "file_path": "src/parser_test.mbt",
            "changed": true,
            "before_fingerprint": "present:test-0",
            "after_fingerprint": "present:test-1",
          },
        ],
      },
    },
  })
  results.push({
    "tool": "moon_cmd",
    "accepted": false,
    "arguments": { "command": "test" },
    "result": { "message": "compiler error in parser branch" },
  })
  results.push({
    "tool": "edit",
    "accepted": true,
    "arguments": { "path": "src/parser.mbt" },
    "result": {
      "message": "repaired compiler diagnostic",
      "metadata": {
        "path": "src/parser.mbt",
        "changed": true,
        "before_fingerprint": "present:parser-1",
        "after_fingerprint": "present:parser-2",
      },
    },
  })
  results.push({
    "tool": "moon_cmd",
    "accepted": true,
    "arguments": { "command": "test" },
    "result": { "message": "tests passed" },
  })
  let final_checkpoint = mooncode_runtime_horizon_checkpoint_execution(
    command,
    "session-horizon",
    "/tmp/book",
    "command-horizon",
    {
      "tool": "checkpoint",
      "arguments": {
        "horizon_id": "horizon-1",
        "milestones": Json::array(
          mooncode_horizon_test_milestones("done", "done", "done"),
        ),
        "next_action": "Finish with the verified result.",
      },
    },
    results,
    now=@clock.Timestamp::from_ms(2L),
  )
  assert_true(mooncode_json_bool(final_checkpoint, "accepted", default=false))
  results.push(final_checkpoint)
  results.push({
    "tool": "finish",
    "accepted": true,
    "result": { "message": "finished" },
  })
  let verdict = mooncode_runtime_turn_completion_verdict(
    command,
    results,
    require_horizon=true,
  )
  assert_true(verdict.accepted)
  let progress = mooncode_runtime_horizon_progress_message(command, results, 3)
  let progress_text = mooncode_json_string(progress, "content", default="")
  assert_true(progress_text.contains("Planner opportunities remaining: 3"))
  assert_true(progress_text.contains("Do not rediscover completed milestones"))
  assert_true(
    progress_text.contains("Authoritative immutable checkpoint contract"),
  )
  assert_true(progress_text.contains("\"horizon_id\": \"horizon-1\""))
  assert_true(progress_text.contains("\"id\": \"implementation\""))
  assert_true(progress_text.contains("\"evidence_kind\": \"mutation\""))
  assert_true(
    progress_text.contains(
      "never guess or reconstruct the contract from memory",
    ),
  )
  assert_true(progress_text.length() < 16000)
  let unbounded = mooncode_runtime_horizon_progress_message(command, results, 0)
  let unbounded_text = mooncode_json_string(unbounded, "content", default="")
  assert_true(unbounded_text.contains("milestone-driven"))
  assert_false(unbounded_text.contains("opportunities remaining"))
  assert_true(
    unbounded_text.contains(
      "task-contract context_paths remain authoritative starting points",
    ),
  )
  assert_true(
    unbounded_text.contains(
      "resolve it with narrow discovery rather than guessing or abandoning",
    ),
  )
  assert_false(unbounded_text.contains("remaining: -1"))
}

///|
test "mooncode long-horizon completion rejects unproven milestone claims" {
  let command : Json = {
    "command": "prompt",
    "command_id": "command-horizon-reject",
    "payload": { "horizon_id": "horizon-reject" },
    "text": "Implement the fix and run tests.",
  }
  let rejected = mooncode_runtime_horizon_checkpoint_execution(
    command,
    "session-horizon",
    "/tmp/book",
    "command-horizon-reject",
    {
      "tool": "checkpoint",
      "arguments": {
        "horizon_id": "horizon-reject",
        "milestones": Json::array(
          mooncode_horizon_test_milestones("done", "done", "done"),
        ),
        "next_action": "Finish.",
      },
    },
    [],
    now=@clock.Timestamp::from_ms(3L),
  )
  assert_false(mooncode_json_bool(rejected, "accepted", default=true))
  let rejected_result = mooncode_json_object_field_or_empty(rejected, "result")
  assert_true(
    mooncode_json_string(rejected_result, "message", default="").contains(
      "no matching runtime evidence",
    ),
  )
  let required_contract = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(rejected_result, "metadata"),
    "required_checkpoint_contract",
  )
  assert_eq(
    mooncode_json_string(required_contract, "horizon_id", default=""),
    "horizon-reject",
  )
  let required_milestones = mooncode_json_array_items(
    required_contract, "milestones",
  )
  assert_eq(required_milestones.length(), 3)
  assert_eq(
    mooncode_json_string(required_milestones[1], "id", default=""),
    "implementation",
  )
  assert_eq(
    mooncode_json_string(required_milestones[1], "evidence_kind", default=""),
    "mutation",
  )
}

///|
test "mooncode long-horizon resume restores only accepted journal checkpoints" {
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": "session-resume",
    "book_root": "/tmp/book",
    "command": "prompt",
    "text": "Implement the fix and run tests.",
    "payload": { "horizon_id": "horizon-resume" },
    "packet": { "command_id": "command-resume" },
  }
  let failed : Json = {
    "tool": "checkpoint",
    "tool_result": {
      "ok": false,
      "metadata": {
        "horizon_id": "horizon-resume",
        "checkpoint": { "milestones": [{ "id": "failed", "status": "done" }] },
      },
    },
  }
  let accepted : Json = {
    "tool": "checkpoint",
    "tool_result": {
      "ok": true,
      "metadata": {
        "horizon_id": "horizon-resume",
        "checkpoint": {
          "milestones": [{ "id": "implementation", "status": "active" }],
        },
      },
    },
  }
  let resumed = mooncode_runtime_horizon_attach_checkpoint(command, [
    failed, accepted,
  ])
  assert_true(
    mooncode_json_bool(
      mooncode_validate_command_body("session-resume", resumed),
      "ok",
      default=false,
    ),
  )
  let checkpoint = mooncode_json_object_field_or_empty(
    mooncode_json_object_field_or_empty(resumed, "payload"),
    "horizon_checkpoint",
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_array_items(checkpoint, "milestones")[0],
      "id",
      default="",
    ),
    "implementation",
  )
}
