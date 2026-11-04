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
  assert_true(
    mooncode_runtime_turn_completion_verdict(command, results).accepted,
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
  let verdict = mooncode_runtime_turn_completion_verdict(command, results)
  assert_true(verdict.accepted)
  assert_eq(
    verdict.reason,
    "coding completion has successful current typed test evidence",
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
