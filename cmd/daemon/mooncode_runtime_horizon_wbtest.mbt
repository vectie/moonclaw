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
  let command : Json = {
    "command": "prompt",
    "text": "Finish the implementation and run tests.",
    "payload": {
      "horizon_id": "terminal-commit",
      "task_contract": {
        "horizon_id": "terminal-commit",
        "objective": "Finish and validate the repair",
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
  let finish : Json = {
    "tool": "finish",
    "accepted": true,
    "result": { "metadata": {} },
  }
  let results = [commit, verification, finish]
  assert_true(
    mooncode_runtime_turn_completion_verdict(command, results).accepted,
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
