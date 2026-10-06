///|
fn model_workspace_fixture_command(
  root : String,
  owner : String,
  id : String,
) -> Json {
  let body : Json = {
    "protocol": mooncode_protocol_version(),
    "command": "prompt",
    "session_id": "model-workspace",
    "book_root": root,
    "model": "moongate/exact-id",
    "text": "Inspect source",
    "packet": { "command_id": id },
  }
  if owner == "" {
    body
  } else {
    mooncode_json_object_with_field(body, "model_workspace", owner.to_json())
  }
}

///|
fn model_workspace_fixture_payload(body : Json) -> Json {
  {
    "kind": "mooncode-command",
    "session_id": "model-workspace",
    "command_id": mooncode_command_id(body),
    "created_at": "fixture",
    "command": body,
  }
}

///|
fn model_workspace_fixture_binding(root : String) -> MoonCodeSessionBinding {
  {
    session_id: "model-workspace",
    book_root: root,
    workspace_id: "",
    workspace_name: "",
    model: "",
    model_workspace: "",
    command_count: 0,
    first_user_prompt: "",
    custom_title: "",
    last_command_id: "",
    last_updated: @clock.epoch.now(),
    runtime_service_running: false,
    runtime_service_wake_pending: false,
    runtime_service_task: None,
    active_command_id: "",
    events: @broadcast.Broadcast::new(),
  }
}

///|
test "model workspace native codec is optional and rejects invalid supplied roots" {
  let legacy = model_workspace_fixture_command("/source", "", "first")
  assert_true(
    mooncode_json_bool(
      mooncode_validate_command_body("model-workspace", legacy),
      "ok",
      default=false,
    ),
  )
  let explicit = model_workspace_fixture_command("/source", "/owner", "first")
  assert_true(
    mooncode_json_bool(
      mooncode_validate_command_body("model-workspace", explicit),
      "ok",
      default=false,
    ),
  )
  for
    root in [
      Json::null(),
      (5).to_json(),
      "".to_json(),
      "relative".to_json(),
      " /owner".to_json(),
    ] {
    let malformed = mooncode_json_object_with_field(
      legacy, "model_workspace", root,
    )
    assert_false(
      mooncode_json_bool(
        mooncode_validate_command_body("model-workspace", malformed),
        "ok",
        default=true,
      ),
    )
  }
  assert_eq(
    mooncode_json_string(
      mooncode_capabilities_payload(),
      "model_workspace_contract",
      default="",
    ),
    "mooncode.model-workspace.v1",
  )
  let tool_body = mooncode_runtime_turn_tool_body(explicit, {
    "tool": "read",
    "arguments": { "path": "README.md" },
  })
  assert_eq(mooncode_book_root(tool_body), "/source")
  assert_eq(mooncode_json_string(tool_body, "model_workspace", default=""), "")
}

///|
async test "model workspace exclusive routing covers admission initial followup and restart seams" {
  let command = model_workspace_fixture_command("/source", "/owner", "first")
  let calls : Array[String] = []
  for phase in ["admission", "initial", "followup", "restart"] {
    let resolved = mooncode_resolve_model_workspace(
      command,
      "moongate/exact-id",
      legacy_source_fallback=phase != "admission",
      owner_lookup=async fn(root, selector) {
        calls.push(root + ":" + selector)
        Some("owner-route")
      },
      daemon_lookup=async fn(_) { fail("must not use daemon same-named route") },
      source_lookup=async fn(_, _) {
        fail("must not use source same-named route")
      },
    )
    assert_eq(resolved, Some("owner-route"))
    assert_eq(mooncode_book_root(command), "/source")
  }
  assert_eq(calls.length(), 4)
  assert_true(calls.all(call => call == "/owner:moongate/exact-id"))
  let missing : String? = mooncode_resolve_model_workspace(
    command,
    "moongate/exact-id",
    owner_lookup=async fn(_, _) { None },
    daemon_lookup=async fn(_) {
      fail("missing owner must not fall back to daemon")
    },
    source_lookup=async fn(_, _) {
      fail("missing owner must not fall back to source")
    },
  )
  assert_true(missing is None)
}

///|
async test "model workspace omitted retains legacy admission and planner fallback" {
  let command = model_workspace_fixture_command("/source", "", "first")
  for fallback in [false, true] {
    let selected = mooncode_resolve_model_workspace(
      command,
      "legacy/selector",
      legacy_source_fallback=fallback,
      owner_lookup=async fn(_, _) { fail("legacy must not consult owner") },
      daemon_lookup=async fn(_) { None },
      source_lookup=async fn(root, selector) {
        assert_eq(root, "/source")
        assert_eq(selector, "legacy/selector")
        Some("source-route")
      },
    )
    assert_eq(selected, if fallback { Some("source-route") } else { None })
  }
}

///|
async test "model workspace journal freezes identity restores without snapshot and inherits continuation" {
  @fsx.with_temporary_directory("mooncode-model-workspace-XXXXXX", async fn(
    root,
  ) {
    let first = model_workspace_fixture_command(root, "/owner", "first")
    assert_true(
      mooncode_persist_bound_command(
        root,
        "model-workspace",
        first,
        model_workspace_fixture_payload(first),
      ),
    )
    assert_false(
      mooncode_persist_bound_command(
        root,
        "model-workspace",
        first,
        model_workspace_fixture_payload(first),
      ),
    )
    let restarted = model_workspace_fixture_binding(root)
    restarted.restore_session_metadata()
    assert_eq(restarted.model_workspace, "/owner")
    assert_eq(restarted.command_count, 1)
    assert_eq(restarted.model, "moongate/exact-id")
    assert_eq(
      mooncode_json_string(
        mooncode_session_snapshot(restarted),
        "model_workspace",
        default="",
      ),
      "/owner",
    )
    let omitted = model_workspace_fixture_command(root, "", "next")
    guard mooncode_command_with_model_workspace(
        omitted,
        Some(restarted.model_workspace),
      )
      is Ok(next) else {
      fail("continuation must inherit")
    }
    assert_eq(
      mooncode_json_string(next, "model_workspace", default=""),
      "/owner",
    )
    assert_true(
      mooncode_persist_bound_command(
        root,
        "model-workspace",
        next,
        model_workspace_fixture_payload(next),
      ),
    )
    for
      changed in [
        mooncode_json_object_with_field(first, "text", "changed".to_json()),
        model_workspace_fixture_command(root, "/different-owner", "first"),
        model_workspace_fixture_command(root, "/different-owner", "new-id"),
        omitted,
      ] {
      let rejected = try {
        ignore(
          mooncode_persist_bound_command(
            root,
            "model-workspace",
            changed,
            model_workspace_fixture_payload(changed),
          ),
        )
        false
      } catch {
        _ => true
      }
      assert_true(rejected)
    }
    assert_true(
      mooncode_command_with_model_workspace(
        model_workspace_fixture_command(root, "/different-owner", "next"),
        Some("/owner"),
      )
      is Err(_),
    )
    assert_true(
      mooncode_command_with_model_workspace(first, Some("")) is Err(_),
    )
    let journal = mooncode_read_session_journal(root, "model-workspace")
    assert_eq(
      mooncode_journal_entries(journal, mooncode_journal_command()).length(),
      2,
    )
    assert_eq(mooncode_journal_model_workspace(journal), Some("/owner"))
    let projected = mooncode_session_record_from_parts_locked(
      "model-workspace",
      root,
      None,
      None,
      source="fixture",
    )
    assert_eq(
      mooncode_json_string(projected, "model_workspace", default=""),
      "/owner",
    )
    assert_eq(mooncode_json_string(projected, "book_root", default=""), root)
  })
}

///|
async test "model workspace concurrent admission cannot freeze different owners" {
  @fsx.with_temporary_directory("mooncode-model-race-XXXXXX", async fn(root) {
    let mut accepted = 0
    @async.with_task_group(async fn(group) {
      let tasks = Array::new(capacity=2)
      for owner in ["/owner-a", "/owner-b"] {
        let body = model_workspace_fixture_command(root, owner, owner)
        tasks.push(
          group.spawn(async fn() {
            mooncode_persist_bound_command(
              root,
              "model-workspace",
              body,
              model_workspace_fixture_payload(body),
            ) catch {
              _ => false
            }
          }),
        )
      }
      for task in tasks {
        if task.wait() {
          accepted += 1
        }
      }
    })
    assert_eq(accepted, 1)
    assert_eq(
      mooncode_journal_entries(
        mooncode_read_session_journal(root, "model-workspace"),
        mooncode_journal_command(),
      ).length(),
      1,
    )
  })
}

///|
async test "model workspace canonical directory validation never rewrites source root" {
  @fsx.with_temporary_directory("mooncode-model-owner-XXXXXX", async fn(root) {
    let canonical = @fs.realpath(root)
    assert_true(mooncode_model_workspace_is_canonical(canonical))
    assert_false(mooncode_model_workspace_is_canonical(canonical + "/."))
    assert_false(mooncode_model_workspace_is_canonical(canonical + "/missing"))
    assert_true(mooncode_model_workspace_is_canonical(""))
  })
}

///|
async test "model workspace legacy journal cannot acquire an owner and conflicting sidecar fails closed" {
  @fsx.with_temporary_directory("mooncode-model-legacy-XXXXXX", async fn(root) {
    let legacy = model_workspace_fixture_command(root, "", "first")
    assert_true(
      mooncode_persist_bound_command(
        root,
        "model-workspace",
        legacy,
        model_workspace_fixture_payload(legacy),
      ),
    )
    let resumed = model_workspace_fixture_binding(root)
    resumed.restore_session_metadata()
    assert_eq(resumed.command_count, 1)
    assert_eq(resumed.model_workspace, "")
    let rooted = model_workspace_fixture_command(root, "/owner", "next")
    assert_true(
      mooncode_command_with_model_workspace(
        rooted,
        Some(resumed.model_workspace),
      )
      is Err(_),
    )
    let rejected = try {
      ignore(
        mooncode_persist_bound_command(
          root,
          "model-workspace",
          rooted,
          model_workspace_fixture_payload(rooted),
        ),
      )
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    resumed.model_workspace = "/wrong-sidecar-owner"
    @fsx.write_to_file(
      mooncode_session_snapshot_path(root, "model-workspace"),
      mooncode_session_snapshot(resumed).stringify(),
    )
    let rejected = try {
      model_workspace_fixture_binding(root).restore_session_metadata()
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  })
}
