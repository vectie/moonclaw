///|
async fn learning_request_write(
  root : String,
  path : String,
  content : String,
) -> Unit {
  let parts = path.split("/").to_array()
  let directory = parts[:parts.length() - 1].to_array().join("/")
  if !@fs.exists(root + "/" + directory) {
    @fs.mkdir(root + "/" + directory, recursive=true)
  }
  @fs.write_file(root + "/" + path, content, create_mode=CreateOrTruncate)
}

///|
fn learning_request_intent(
  source_root : String,
) -> @job.SupervisorDelegateIntentRequestV1 raise {
  let request : @job.SupervisorDelegateIntentRequestV1 = {
    envelope: {
      contract_id: "moonclaw.supervisor-command.v1",
      command_id: "native-learning-request-fixture",
      request_digest: "sha256:" + "a".repeat(64),
      issued_at: @job.supervisor_epoch_ms_v1(1790942400000L),
      evaluated_at: "2026-10-02T12:00:00Z",
      expected_cursor: None,
      authority: {},
    },
    supervisor_id: "learning-supervisor",
    instruction: "Evaluate only the authorized artifact and return bounded evidence.",
    task: {
      task_id: "learning-request-task",
      conversation_id: "learning-request-conversation",
      title: "Selected Book learned input proof",
      cwd: source_root,
      model: Some("moongate/exact-selected-fixture"),
      web_search: false,
      metadata: {
        "workspace_id": "selected-suite",
        "book_id": "differently-named-import",
      },
    },
    scope: {
      claim_ceiling: "evidence-only",
      budget: {
        max_cost_micro_usd: 1L,
        max_runtime_ms: 60000L,
        max_tokens: 16000L,
        max_artifacts: 2,
      },
      artifact_prefixes: ["artifacts/learning-supervisor/authorized-only"],
      expires_at: "2026-10-02T13:00:00Z",
    },
  }
  let payload = @job.supervisor_delegate_intent_payload_v1(
    request.supervisor_id,
    request.instruction,
    request.task,
    request.scope,
  )
  {
    ..request,
    envelope: learning_native_envelope(
      "native-learning-request-fixture", payload,
    ),
  }
}

///|
fn learning_native_receiver() -> @capability.PrincipalRefV1 raise {
  @capability.principal_ref_v1(
    "native-learning-fixture",
    Service,
    "moonclaw",
    "native-learning-fixture",
  )
}

///|
fn learning_native_envelope(
  command : String,
  payload : Json,
) -> @job.SupervisorCommandEnvelopeV1 raise {
  let envelope : @job.SupervisorCommandEnvelopeV1 = {
    contract_id: "moonclaw.supervisor-command.v1",
    command_id: command,
    request_digest: "",
    issued_at: @job.supervisor_epoch_ms_v1(1790942400000L),
    evaluated_at: "2026-10-02T12:00:00Z",
    expected_cursor: None,
    authority: Json::null(),
  }
  let digest = @job.supervisor_command_digest_v1(envelope, payload)
  {
    ..envelope,
    request_digest: digest,
    authority: @capability.encode_authority_decision_ref_v1(
      @capability.authority_decision_ref_v1(
        command + "-authority",
        learning_native_receiver(),
        digest,
        envelope.evaluated_at,
        "2026-10-02T13:00:00Z",
      ),
    ),
  }
}

///|
async fn learning_native_runtime(root : String) -> @job.SupervisorRuntime {
  let runtime = @job.RuntimeManager::new(root~)
  let supervisor = @job.SupervisorRuntime::new(
    runtime~,
    receiver=learning_native_receiver(),
    verifier=@job.SupervisorAuthorityVerifierV1::new(verify=(
      envelope,
      operation,
    ) => {
      Ok({
        operation_ref: operation,
        operation_digest: "sha256:" + "b".repeat(64),
        capability_resolution: {},
        verified_at: envelope.evaluated_at,
      })
    }),
  )
  supervisor.load()
  supervisor
}

///|
async fn learning_native_activate(supervisor : @job.SupervisorRuntime) -> Unit {
  let runtime_profile : Json = {
    "purpose": "hermetic-serialized-native-learning-proof",
  }
  let profile : @job.SupervisorProfileActivationV1 = {
    contract_id: "moonsuite.supervisor-profile-activation.v1",
    supervisor_id: "learning-supervisor",
    profile_id: "fixture-profile",
    profile_version: 1,
    profile_digest: @book_learning.digest(
      @encoding/utf8.encode(runtime_profile.stringify()),
    ),
    source_product: "moontown",
    runtime_profile,
    runtime_binding: { "max_active_workers": 16 },
    activated_at: @job.supervisor_epoch_ms_v1(1790942400000L),
  }
  let envelope = learning_native_envelope(
    "native-learning-activate",
    @job.supervisor_activate_payload_v1(profile),
  )
  match
    supervisor.activate_profile({ envelope, profile, }, "native-parent-run") {
    Ok(_) => ()
    Err(error) => fail("Activation failed: " + error)
  }
}

///|
async fn learning_request_capture(root : String) -> @book_learning.Snapshot {
  let contract = @json.parse(
    @fs.read_file("internal/book_learning/testdata/accepted-memory-v1.json").text(),
  )
  guard contract
    is {
      "desk_imported_records": Array(records),
      "imported_files": Array(imported_files),
      ..
    } else {
    fail("Missing frozen actual Desk import records and installation")
  }
  assert_eq(records.length(), 4)
  for record in records {
    guard record
      is {
        "path": String(path),
        "content": String(content),
        "sha256": String(hash),
        ..
      } else {
      fail("Invalid Desk record")
    }
    assert_eq(@book_learning.digest(@encoding/utf8.encode(content)), hash)
    learning_request_write(root, path, content)
  }
  for file in imported_files {
    guard file
      is {
        "path": String(path),
        "content": String(content),
        "sha256": String(hash),
        ..
      } else {
      fail("Invalid real import metadata")
    }
    assert_eq(@book_learning.digest(@encoding/utf8.encode(content)), hash)
    learning_request_write(root, path, content)
  }
  let long_record : Json = {
    "status": "accepted",
    "category": "procedure",
    "title": "Full Bookkeeper tail obligation fixture",
    "procedure": "Preserve the ordered procedure and explicit evidence. ".repeat(
      220,
    ),
    "provenance": "bookkeeper:accepted:source-version-7/" +
    "long-provenance-".repeat(100) +
    "PROVENANCE_END_NATIVE_94",
    "applicability": "Only inside the selected bounded artifact scope: APPLY_END_NATIVE_91_尾部",
    "verification": "Re-read every produced byte and compare the digest: VERIFY_END_NATIVE_92",
    "counterexamples": "Do not apply after a capability change: COUNTEREXAMPLE_END_NATIVE_93",
    "invalidation": "Reject stale evidence instead of guessing: INVALIDATION_END_NATIVE_95",
  }
  learning_request_write(
    root,
    "memory/procedures/zz-bookkeeper-tail.json",
    long_record.stringify(indent=2),
  )
  learning_request_write(
    root, "memory/procedures/candidate.json", "{\"status\":\"candidate\",\"accepted\":true,\"note\":\"CANDIDATE_NATIVE_MUST_NOT_SEND\"}",
  )
  learning_request_write(
    root, "memory/beliefs/nested.json", "{\"nested\":{\"status\":\"accepted\"},\"note\":\"NESTED_NATIVE_MUST_NOT_SEND\"}",
  )
  learning_request_write(
    root, "memory/beliefs/rejected.json", "{\"status\":\"rejected\",\"note\":\"REJECTED_NATIVE_MUST_NOT_SEND\"}",
  )
  let snapshot = @book_learning.capture(
    {
      workspace_id: "selected-suite",
      book_id: "differently-named-import",
      source_root: root,
      request_digest: "sha256:" + "a".repeat(64),
    },
    1790942400,
  )
  assert_eq(snapshot.status, "ready")
  assert_eq(snapshot.records.length(), 5)
  assert_eq(snapshot.excluded_records, 3)
  for record in records {
    guard record is { "path": String(path), "content": String(content), .. } else {
      fail("Invalid frozen record")
    }
    assert_eq(@fs.read_file(root + "/" + path).text(), content)
  }
  assert_eq(
    @fs.read_file(root + "/memory/procedures/zz-bookkeeper-tail.json").text(),
    long_record.stringify(indent=2),
  )
  for file in imported_files {
    guard file is { "path": String(path), "content": String(content), .. } else {
      fail("Invalid real import metadata")
    }
    assert_eq(@fs.read_file(root + "/" + path).text(), content)
  }
  let installation = @json.parse(
    @fs.read_file(root + "/state/agent-installation.json").text(),
  )
  guard installation
    is {
      "agent_id": String(agent_id),
      "version": String(version),
      "bundle_digest": String(bundle_digest),
      "receipt_path": String(receipt_path),
      ..
    } else {
    fail("Invalid imported installation tuple")
  }
  assert_eq(agent_id, "portable-learning")
  assert_eq(version, "3.2.1")
  assert_eq(snapshot.installation_lineage, {
    "agent_id": agent_id,
    "version": version,
    "bundle_digest": bundle_digest,
    "receipt_path": receipt_path,
  })
  guard @book_learning.summary(snapshot)
    is { "installation_lineage": lineage, .. } else {
    fail("Missing safe lineage summary")
  }
  assert_eq(lineage, {
    "agent_id": agent_id,
    "version": version,
    "bundle_digest": bundle_digest,
  })
  assert_false(lineage.stringify().contains("receipt_path"))
  snapshot
}

///|
fn learning_request_user_text(body : String) -> String raise {
  guard @json.parse(body) is { "messages": Array(messages), .. } else {
    fail("Missing final serialized messages")
  }
  let text = StringBuilder()
  for message in messages {
    match message {
      { "role": String("user"), "content": String(content), .. } =>
        text.write_string(content)
      { "role": String("user"), "content": Array(parts), .. } =>
        for part in parts {
          if part is { "type": String("text"), "text": String(content), .. } {
            text.write_string(content)
          }
        }
      _ => ()
    }
  }
  text.to_string()
}

///|
fn learning_request_completion(
  content : String,
) -> @openai.ChatCompletion raise {
  @json.from_json({
    "id": "native-serialized-request-proof",
    "model": "exact-selected-fixture",
    "choices": [
      {
        "index": 0,
        "message": { "role": "assistant", "content": content },
        "finish_reason": "stop",
      },
    ],
  })
}

///|
fn learning_assert_native_wire_schema(body : String) -> Unit raise {
  guard @json.parse(body) is Object(fields) else {
    fail("Expected standard request object")
  }
  let keys = fields.keys().to_array()
  assert_eq(keys.length(), 3)
  assert_true(keys.all(key => ["messages", "model", "stream"].contains(key)))
  assert_eq(fields["model"], Json::string("exact-selected-fixture"))
  assert_eq(fields["stream"], Json::boolean(true))
  // The fixture intentionally registers no tools. No optional descriptor,
  // integrity metadata, captured snapshot, or new tool schema is an API field.
  assert_false(fields.contains("tools"))
  guard fields["messages"] is Array(messages) else {
    fail("Expected messages array")
  }
  for message in messages {
    guard message is Object(message) else {
      fail("Expected standard message object")
    }
    let keys = message.keys().to_array()
    assert_eq(keys.length(), 2)
    assert_true(keys.all(key => ["content", "role"].contains(key)))
    if message["content"] is Array(parts) {
      for part in parts {
        guard part is Object(part) else {
          fail("Expected standard content part")
        }
        assert_eq(part["type"], Json::string("text"))
        for key, _ in part {
          assert_true(["type", "text", "cache_control"].contains(key))
        }
      }
    }
  }
}

///|
/// Hermetic proof stops at the real serialized transport seam. It does not
/// claim a listening socket, native child launch, or live-provider execution.
async test "actual imported Desk and Bookkeeper records reach native serialized supervisor request" {
  let root = @fs.tmpdir(prefix="supervisor-learning-request-")
  defer @fs.rmdir(root, recursive=true)
  let source = root + "/differently-named-import"
  let execution = root + "/private-supervisor-worker"
  @fs.mkdir(execution, recursive=true)
  let fixture_capture = learning_request_capture(source)
  let before_book = @fs.read_file(source + "/book.toml").binary()
  let before_lineage = @fs.read_file(source + "/state/agent-installation.json").binary()
  let request = learning_request_intent(source) catch {
    error => fail("intent fixture: \{Repr(error)}")
  }
  let runtime = learning_native_runtime(root + "/durable-runtime") catch {
    error => fail("runtime fixture: \{Repr(error)}")
  }
  learning_native_activate(runtime) catch {
    error => fail("activation fixture: \{Repr(error)}")
  }
  let delegation = runtime.delegate_intent(
    request, "worker-native-fixture", "local-unmetered",
  ) catch {
    error => fail("delegation fixture: \{Repr(error)}")
  }
  let prepared = match delegation {
    Ok(prepared) => prepared
    Err(error) => fail("Durable delegate failed: " + error)
  }
  let snapshot = match
    runtime.worker_learning_input(request.supervisor_id, prepared.worker_run_id) {
    Ok(snapshot) => snapshot
    Err(error) => fail("Durable captured input unavailable: " + error)
  }
  assert_eq(snapshot.records, fixture_capture.records)
  assert_eq(
    snapshot.source_binding.request_digest,
    request.envelope.request_digest,
  )
  assert_false(
    prepared.receipt.to_json().stringify().contains("PROVENANCE_END_NATIVE_94"),
  )
  let prompt = supervisor_worker_prompt(
    request,
    prepared.worker_run_id,
    book_learning=snapshot,
  )
  let outgoing = @server.CreateMessageRequest::new(
    message=@ai.user_message(content=prompt),
    optional_context?=supervisor_worker_optional_context(snapshot),
  )
  let incoming : @server.CreateMessageRequest = @json.from_json(
    @json.parse(outgoing.to_json().stringify()),
  )
  let mut calls = 0
  let model = @model.new(
    api_key="",
    base_url="https://native-transport.invalid/openclaw/v1",
    name="moongate/exact-selected-fixture",
    model_name="exact-selected-fixture",
    safe_zone_tokens=128000,
  )
  let agent = @agent.new(
    model,
    cwd=execution,
    home=root,
    logger=@pino.logger("native-learning-proof", @pino.Transport::sink()),
    workspace_trust="untrusted",
    chat_transport=(wire, on_delta) => {
      calls += 1
      learning_assert_native_wire_schema(wire.body)
      assert_eq(
        wire.url,
        "https://native-transport.invalid/openclaw/v1/chat/completions",
      )
      assert_false(wire.headers.contains("Authorization"))
      assert_true(wire.stream)
      guard @json.parse(wire.body)
        is { "model": String("exact-selected-fixture"), .. } else {
        fail("Native model route changed")
      }
      let text = learning_request_user_text(wire.body)
      assert_eq(text, prompt)
      assert_true(text.contains(source))
      assert_false(text.contains(execution))
      assert_true(
        text.contains("artifacts/learning-supervisor/authorized-only"),
      )
      assert_true(text.contains("Capability lessons remain ideas"))
      assert_true(text.contains(snapshot.content_digest))
      assert_false(text.contains("CANDIDATE_NATIVE_MUST_NOT_SEND"))
      assert_false(text.contains("NESTED_NATIVE_MUST_NOT_SEND"))
      assert_false(text.contains("REJECTED_NATIVE_MUST_NOT_SEND"))
      // Decode the exact canonical record array inside the final model message,
      // then compare raw content and digests instead of substring-only evidence.
      let record_json = snapshot.records.to_json().stringify(indent=2)
      guard text.find(record_json) is Some(record_start) else {
        fail("Complete record array is absent from final request")
      }
      let wire_records = text[record_start:record_start + record_json.length()].to_owned()
      let decoded : Array[@book_learning.Record] = @json.from_json(
        @json.parse(wire_records),
      )
      assert_eq(decoded.length(), 5)
      for index, record in decoded {
        assert_eq(record.content_utf8, snapshot.records[index].content_utf8)
        assert_eq(
          @book_learning.digest(@encoding/utf8.encode(record.content_utf8)),
          record.sha256,
        )
      }
      assert_true(text.contains("APPLY_END_NATIVE_91_尾部"))
      assert_true(text.contains("VERIFY_END_NATIVE_92"))
      assert_true(text.contains("COUNTEREXAMPLE_END_NATIVE_93"))
      assert_true(text.contains("PROVENANCE_END_NATIVE_94"))
      assert_true(text.contains("INVALIDATION_END_NATIVE_95"))
      on_delta("exact complete accepted records observed")
      learning_request_completion("exact complete accepted records observed")
    },
  )
  let _ = incoming.queue_on(agent)
  agent.start()
  assert_eq(calls, 1)
  assert_eq(agent.cwd, execution)
  assert_eq(agent.model.name, "moongate/exact-selected-fixture")
  assert_true(agent.tools().is_empty())
  assert_eq(agent.optional_context_statuses()[0].status, "ready")
  assert_eq(@fs.read_file(source + "/book.toml").binary(), before_book)
  assert_eq(
    @fs.read_file(source + "/state/agent-installation.json").binary(),
    before_lineage,
  )
  for record in snapshot.records {
    assert_eq(
      @fs.read_file(source + "/" + record.path).binary(),
      @encoding/utf8.encode(record.content_utf8),
    )
  }

  // Persistence is exercised through the full snapshot JSON, then the source
  // is deliberately changed. This request still uses the saved exact bytes.
  learning_request_write(
    source, "memory/procedures/zz-bookkeeper-tail.json", "{\"status\":\"accepted\",\"note\":\"MUTATED_SOURCE_MUST_NOT_REHYDRATE\"}",
  )
  let reopened = learning_native_runtime(root + "/durable-runtime")
  let duplicate = match
    reopened.delegate_intent(
      request, "ignored-new-provider-id", "local-unmetered",
    ) {
    Ok(value) => value
    Err(error) => fail("Duplicate after source mutation failed: " + error)
  }
  assert_true(duplicate.receipt.duplicate)
  let saved = match
    reopened.worker_learning_input(
      request.supervisor_id,
      prepared.worker_run_id,
    ) {
    Ok(value) => value
    Err(error) => fail("Restored durable input unavailable: " + error)
  }
  assert_eq(saved, snapshot)
  assert_true(@book_learning.validate(saved, snapshot.source_binding) is Ok(_))
  let retry_prompt = supervisor_worker_prompt(
    request,
    prepared.worker_run_id,
    retry_reason="saved snapshot retry",
    book_learning=saved,
  )
  let retry = @server.CreateMessageRequest::new(
    message=@ai.user_message(content=retry_prompt),
    optional_context?=supervisor_worker_optional_context(saved),
  )
  let restored : @server.CreateMessageRequest = @json.from_json(
    @json.parse(retry.to_json().stringify()),
  )
  let replay = @agent.new(
    model,
    cwd=execution,
    home=root,
    logger=@pino.logger("native-learning-replay", @pino.Transport::sink()),
    workspace_trust="untrusted",
    chat_transport=(wire, _) => {
      calls += 1
      learning_assert_native_wire_schema(wire.body)
      let text = learning_request_user_text(wire.body)
      assert_eq(text, retry_prompt)
      assert_true(text.contains("INVALIDATION_END_NATIVE_95"))
      assert_false(text.contains("MUTATED_SOURCE_MUST_NOT_REHYDRATE"))
      learning_request_completion("saved snapshot observed")
    },
  )
  let _ = restored.queue_on(replay)
  replay.start()
  assert_eq(calls, 2)
}
