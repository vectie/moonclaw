///|
fn learning_receiver() -> @capability.PrincipalRefV1 raise {
  @capability.principal_ref_v1(
    "learning-fixture",
    Service,
    "moonclaw",
    "learning-fixture",
  )
}

///|
fn learning_envelope(
  command : String,
  payload : Json,
) -> SupervisorCommandEnvelopeV1 raise {
  let envelope : SupervisorCommandEnvelopeV1 = {
    contract_id: "moonclaw.supervisor-command.v1",
    command_id: command,
    request_digest: "",
    issued_at: supervisor_epoch_ms_v1(1790950000000L),
    evaluated_at: "2026-08-01T00:00:00Z",
    expected_cursor: None,
    authority: Json::null(),
  }
  let digest = supervisor_command_digest_v1(envelope, payload)
  {
    ..envelope,
    request_digest: digest,
    authority: @capability.encode_authority_decision_ref_v1(
      @capability.authority_decision_ref_v1(
        command + "-authority",
        learning_receiver(),
        digest,
        envelope.evaluated_at,
        "2026-08-01T01:00:00Z",
      ),
    ),
  }
}

///|
async fn learning_runtime(root : String) -> SupervisorRuntime {
  let runtime = RuntimeManager::new(root~)
  runtime.load() catch {
    error => fail("load runtime: \{Repr(error)}")
  }
  let supervisor = SupervisorRuntime::new(
    runtime~,
    receiver=learning_receiver(),
    verifier=SupervisorAuthorityVerifierV1::new(verify=(envelope, operation) => {
      Ok({
        operation_ref: operation,
        operation_digest: "sha256:" + "b".repeat(64),
        capability_resolution: {},
        verified_at: envelope.evaluated_at,
      })
    }),
  )
  supervisor.reload_unlocked()
  supervisor
}

///|
async fn learning_activate(supervisor : SupervisorRuntime) -> Unit {
  let runtime_profile : Json = { "purpose": "hermetic-learning-test" }
  let profile : SupervisorProfileActivationV1 = {
    contract_id: "moonsuite.supervisor-profile-activation.v1",
    supervisor_id: "supervisor-1",
    profile_id: "fixture-profile",
    profile_version: 1,
    profile_digest: @book_learning.digest(
      @encoding/utf8.encode(runtime_profile.stringify()),
    ),
    source_product: "moontown",
    runtime_profile,
    runtime_binding: { "max_active_workers": 16 },
    activated_at: supervisor_epoch_ms_v1(1790950000000L),
  }
  let envelope = learning_envelope(
    "activate",
    supervisor_activate_payload_v1(profile),
  ) catch {
    error => fail("activate envelope: \{Repr(error)}")
  }
  let result = supervisor.activate_profile({ envelope, profile, }, "parent-run") catch {
    error => fail("activate runtime: \{Repr(error)}")
  }
  match result {
    Ok(_) => ()
    Err(error) => fail("Activation failed: " + error)
  }
}

///|
fn learning_request(
  root : String,
  command : String,
) -> SupervisorDelegateIntentRequestV1 raise {
  let template = supervisor_worker_test_request(max_cost_micro_usd=1L)
  let task = {
    ..template.task,
    cwd: root,
    task_id: command,
    model: Some("moongate/learning-fixture"),
    metadata: { "workspace_id": "selected-suite", "book_id": "relocated-book" },
  }
  let payload = supervisor_delegate_intent_payload_v1(
    template.supervisor_id,
    template.instruction,
    task,
    template.scope,
  )
  { ..template, task, envelope: learning_envelope(command, payload), }
}

///|
async fn learning_write(root : String, content : String) -> Unit {
  if !@fs.exists(root + "/memory/procedures") {
    @fs.mkdir(root + "/memory/procedures", recursive=true)
  }
  @fs.write_file(
    root + "/memory/procedures/lesson.md",
    "---\nstatus: accepted\n---\n" + content,
    create_mode=CreateOrTruncate,
  )
}

///|
async test "durable selected Book captures once across duplicate retry restart and new command" {
  let root = @fs.tmpdir(prefix="claw-learning-runtime-")
  defer @fs.rmdir(root, recursive=true)
  let book = root + "/book"
  learning_write(book, "ORIGINAL_FULL_TAIL")
  let first = learning_runtime(root + "/runtime")
  learning_activate(first)
  let second = learning_runtime(root + "/runtime")
  let request = learning_request(book, "delegate-one")
  let result = first.delegate_intent(request, "worker-one", "local-unmetered") catch {
    error => fail("delegate: \{Repr(error)}")
  }
  let prepared = match result {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let saved = match first.worker_learning_input("supervisor-1", "worker-one") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(saved.status, "ready")
  assert_true(saved.records[0].content_utf8.contains("ORIGINAL_FULL_TAIL"))
  assert_false(
    prepared.receipt.to_json().stringify().contains("ORIGINAL_FULL_TAIL"),
  )
  learning_write(book, "CHANGED_NEW_TAIL")
  let duplicate = match
    second.delegate_intent(request, "ignored-provider-id", "local-unmetered") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(duplicate.receipt.duplicate)
  assert_eq(
    second.worker_learning_input("supervisor-1", "worker-one"),
    Ok(saved),
  )
  let same_payload = supervisor_delegate_intent_payload_v1(
    request.supervisor_id,
    request.instruction,
    request.task,
    request.scope,
  )
  let reissued = {
    ..request,
    envelope: learning_envelope("new-command-same-payload", same_payload),
  }
  assert_eq(reissued.envelope.request_digest, request.envelope.request_digest)
  assert_eq(
    second.worker_definition_provider_id(reissued),
    Ok(Some("worker-one")),
  )
  assert_true(
    second.delegate_intent(reissued, "worker-one", "local-unmetered") is Ok(_),
  )
  assert_eq(
    second.worker_learning_input("supervisor-1", "worker-one"),
    Ok(saved),
  )
  ignore(second.runtime.cancel_run("worker-one", 2))
  let payload = supervisor_worker_retry_payload_v1(
    "supervisor-1", "worker-one", "retry original input",
  )
  let retry = SupervisorWorkerRetryRequestV1::{
    envelope: learning_envelope("retry-one", payload),
    supervisor_id: "supervisor-1",
    worker_run_id: "worker-one",
    reason: "retry original input",
  }
  assert_true(second.verify_worker_retry(retry) is Ok(None))
  assert_true(second.worker_retry(retry, { "accepted": true }) is Ok(_))
  @fs.remove(book + "/memory/procedures/lesson.md")
  let restarted = learning_runtime(root + "/runtime")
  assert_eq(
    restarted.worker_learning_input("supervisor-1", "worker-one"),
    Ok(saved),
  )
  let original_intent = match
    restarted.worker_intent("supervisor-1", "worker-one") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(original_intent.task, request.task)
  assert_eq(original_intent.scope, request.scope)
  learning_write(book, "CHANGED_NEW_TAIL")
  let newer = learning_request(book, "delegate-two")
  assert_true(
    restarted.delegate_intent(newer, "worker-two", "local-unmetered") is Ok(_),
  )
  let next = match
    restarted.worker_learning_input("supervisor-1", "worker-two") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(next.records[0].content_utf8.contains("CHANGED_NEW_TAIL"))
  assert_true(next.content_digest != saved.content_digest)
}

///|
async test "definition before journal crash preserves first capture across stale loaded runtimes" {
  let root = @fs.tmpdir(prefix="claw-learning-crash-")
  defer @fs.rmdir(root, recursive=true)
  let book = root + "/book"
  learning_write(book, "FIRST_BEFORE_CRASH")
  let first = learning_runtime(root + "/runtime")
  learning_activate(first)
  let journal_before = @fs.read_file(first.journal_file()).text()
  let stale = learning_runtime(root + "/runtime")
  let request = learning_request(book, "crash-command")
  assert_true(
    first.delegate_intent(request, "worker-crash", "local-unmetered") is Ok(_),
  )
  let saved = first.worker_learning_input("supervisor-1", "worker-crash")
  @fs.write_file(
    first.journal_file(),
    journal_before,
    create_mode=CreateOrTruncate,
  )
  learning_write(book, "MUTABLE_AFTER_CRASH")
  assert_eq(
    stale.worker_definition_provider_id(request),
    Ok(Some("worker-crash")),
  )
  assert_true(
    stale.delegate_intent(request, "worker-crash", "local-unmetered") is Ok(_),
  )
  assert_eq(stale.worker_learning_input("supervisor-1", "worker-crash"), saved)
  // A genuine old-format definition in the same crash window stays legacy.
  let id = "moonclaw.supervisor-worker." +
    request.envelope.request_digest[7:31].to_owned()
  let definition = stale.runtime.store().get_definition(id).unwrap()
  guard definition.config is Object(fields) else { fail("Invalid config") }
  let legacy_fields = fields.copy()
  legacy_fields.remove("book_learning_input")
  legacy_fields.remove("book_learning_input_contract")
  stale.runtime.register_definition({
    ..definition,
    config: Json::object(legacy_fields),
  })
  @fs.write_file(
    first.journal_file(),
    journal_before,
    create_mode=CreateOrTruncate,
  )
  assert_true(
    stale.delegate_intent(request, "worker-crash", "local-unmetered") is Ok(_),
  )
  let legacy = match
    stale.worker_learning_input("supervisor-1", "worker-crash") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(legacy.status, "legacy_not_captured")
  assert_eq(legacy.records.length(), 0)
}

///|
async test "captured input corruption cannot silently become legacy or recapture current Book" {
  let root = @fs.tmpdir(prefix="claw-learning-corrupt-")
  defer @fs.rmdir(root, recursive=true)
  let book = root + "/book"
  learning_write(book, "CAPTURED_SECRET_TAIL")
  let supervisor = learning_runtime(root + "/runtime")
  learning_activate(supervisor)
  let request = learning_request(book, "corrupt-command")
  let prepared = match
    supervisor.delegate_intent(request, "worker-corrupt", "local-unmetered") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let definition = supervisor.runtime
    .store()
    .get_definition(prepared.worker_job_id)
    .unwrap()
  guard definition.config is Object(fields) else { fail("Invalid config") }
  let stripped = fields.copy()
  stripped.remove("book_learning_input")
  supervisor.runtime.register_definition({
    ..definition,
    config: Json::object(stripped),
  })
  learning_write(book, "MUST_NOT_REREAD")
  assert_true(
    supervisor.worker_learning_input("supervisor-1", "worker-corrupt") is Err(_),
  )
  stripped.remove("book_learning_input_contract")
  supervisor.runtime.register_definition({
    ..definition,
    config: Json::object(stripped),
  })
  assert_true(
    supervisor.worker_learning_input("supervisor-1", "worker-corrupt") is Err(_),
  )
  supervisor.runtime.register_definition(definition)
  let corrupted = fields.copy()
  guard corrupted["book_learning_input"] is Object(snapshot) else {
    fail("Invalid snapshot")
  }
  let snapshot = snapshot.copy()
  snapshot["content_digest"] = "sha256:corrupt"
  corrupted["book_learning_input"] = Json::object(snapshot)
  supervisor.runtime.register_definition({
    ..definition,
    config: Json::object(corrupted),
  })
  assert_true(
    supervisor.worker_learning_input("supervisor-1", "worker-corrupt") is Err(_),
  )
}

///|
async test "public definition redaction and ordinary edits retain immutable host learning" {
  let root = @fs.tmpdir(prefix="claw-learning-public-")
  defer @fs.rmdir(root, recursive=true)
  learning_write(root + "/book", "PRIVATE_CAPTURE_BODY")
  let supervisor = learning_runtime(root + "/runtime")
  learning_activate(supervisor)
  let request = learning_request(root + "/book", "public-command")
  let prepared = match
    supervisor.delegate_intent(request, "worker-public", "local-unmetered") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  let store = supervisor.runtime.store()
  let definition = store.get_definition(prepared.worker_job_id).unwrap()
  let stale_store = SystemStore::new(root=root + "/runtime")
  stale_store.load()
  assert_false(
    definition.public_json().stringify().contains("PRIVATE_CAPTURE_BODY"),
  )
  assert_false(definition.public_json().stringify().contains("source_root"))
  let public : JobDefinition = @json.from_json(definition.public_json())
  let edited = match
    store.prepare_public_definition({
      ..public,
      enabled: false,
      kind: "ordinary-kind",
    }) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_false(edited.enabled)
  assert_eq(edited.config, definition.config)
  assert_false(
    edited.public_json().stringify().contains("PRIVATE_CAPTURE_BODY"),
  )
  assert_true(
    store.prepare_public_definition({ ..public, config: Json::null(), })
    is Err(_),
  )
  guard public.config is Object(fields) else { fail("Invalid config") }
  let changed = fields.copy()
  changed["book_learning_input"] = { "injected": true }
  assert_true(
    store.prepare_public_definition({ ..public, config: Json::object(changed), })
    is Err(_),
  )
  let ordinary = {
    ..public,
    id: "ordinary",
    kind: "ordinary",
    config: Json::null(),
  }
  assert_true(store.prepare_public_definition(ordinary) is Ok(_))
  let later = learning_request(root + "/book", "later-command")
  let later_prepared = match
    supervisor.delegate_intent(later, "worker-later", "local-unmetered") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_true(
    stale_store.save_public_definition({ ..public, enabled: false, }) is Ok(_),
  )
  stale_store.save_definition(ordinary)
  stale_store.save_workflow({
    id: "ordinary-workflow",
    kind: "ordinary",
    steps: [],
    output_bindings: [],
  })
  let reloaded = learning_runtime(root + "/runtime")
  assert_true(
    reloaded.runtime.store().get_definition(later_prepared.worker_job_id)
    is Some(_),
  )
  assert_true(
    reloaded.worker_learning_input("supervisor-1", "worker-later") is Ok(_),
  )
  assert_true(
    reloaded.worker_learning_input("supervisor-1", "worker-public") is Ok(_),
  )
  let ordinary_updated = {
    ..ordinary,
    enabled: false,
    config: { "ordinary_edit": "retained" },
    schedule: Some({
      kind: "interval",
      interval_minutes: Some(30),
      timezone: Some("UTC"),
    }),
  }
  let stored_ordinary = match
    stale_store.save_public_definition(ordinary_updated) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(stored_ordinary.to_json(), ordinary_updated.to_json())
  let final_store = SystemStore::new(root=root + "/runtime")
  final_store.load()
  assert_eq(
    final_store.get_definition("ordinary").unwrap().to_json(),
    ordinary_updated.to_json(),
  )
  assert_eq(stored_ordinary.public_json(), stored_ordinary.to_json())
}

///|
test "legacy definition and alias selection preserve supported behavior" {
  let request = learning_request("/book", "legacy")
  let definition : JobDefinition = {
    id: "legacy",
    kind: "job.supervisor-worker",
    enabled: true,
    config: {
      "intent": supervisor_delegate_intent_payload_v1(
        request.supervisor_id,
        request.instruction,
        request.task,
        request.scope,
      ),
    },
    schedule: None,
    retry_policy: None,
    workflow_id: None,
    created_at: 0,
    updated_at: 0,
    tags: [],
  }
  let legacy = match
    supervisor_learning_from_definition(definition, request, None) {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(legacy.status, "legacy_not_captured")
  assert_true(
    supervisor_learning_from_definition(
      definition,
      request,
      Some(@book_learning.summary(legacy)),
    )
    is Ok(_),
  )
  assert_eq(
    supervisor_learning_alias(
      { "book_id": "", "bookId": "alias" },
      "book_id",
      "bookId",
    ),
    "alias",
  )
}

///|
async test "unavailable and empty durable optional input remain frozen after source appears" {
  let root = @fs.tmpdir(prefix="claw-learning-optional-")
  defer @fs.rmdir(root, recursive=true)
  let supervisor = learning_runtime(root + "/runtime")
  learning_activate(supervisor)
  let request = learning_request(root + "/book", "missing")
  assert_true(
    supervisor.delegate_intent(request, "worker-missing", "local-unmetered")
    is Ok(_),
  )
  let missing = match
    supervisor.worker_learning_input("supervisor-1", "worker-missing") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(missing.status, "unavailable")
  @fs.mkdir(root + "/book")
  let request2 = learning_request(root + "/book", "empty")
  assert_true(
    supervisor.delegate_intent(request2, "worker-empty", "local-unmetered")
    is Ok(_),
  )
  let empty = match
    supervisor.worker_learning_input("supervisor-1", "worker-empty") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(empty.status, "empty")
  learning_write(root + "/book", "LATER_NOT_RETROACTIVE")
  let restarted = learning_runtime(root + "/runtime")
  assert_eq(
    restarted.worker_learning_input("supervisor-1", "worker-missing"),
    Ok(missing),
  )
  assert_eq(
    restarted.worker_learning_input("supervisor-1", "worker-empty"),
    Ok(empty),
  )
  let task = { ..request2.task, task_id: "ordinary", metadata: {}, }
  let nonbook = {
    ..request2,
    task,
    envelope: learning_envelope(
      "ordinary",
      supervisor_delegate_intent_payload_v1(
        request2.supervisor_id,
        request2.instruction,
        task,
        request2.scope,
      ),
    ),
  }
  assert_true(
    restarted.delegate_intent(nonbook, "worker-ordinary", "local-unmetered")
    is Ok(_),
  )
  let ordinary = match
    restarted.worker_learning_input("supervisor-1", "worker-ordinary") {
    Ok(value) => value
    Err(error) => fail(error)
  }
  assert_eq(ordinary.status, "not_applicable")
}

///|
async test "concurrent independently loaded runtimes share one durable learning capture" {
  let root = @fs.tmpdir(prefix="claw-learning-concurrent-")
  defer @fs.rmdir(root, recursive=true)
  learning_write(root + "/book", "ONE_IMMUTABLE_CAPTURE")
  let first = learning_runtime(root + "/runtime")
  learning_activate(first)
  let second = learning_runtime(root + "/runtime")
  let request = learning_request(root + "/book", "concurrent")
  let receipts : Array[SupervisorDelegateIntentPreparedV1] = []
  @async.with_task_group(group => {
    group.spawn_bg(() => {
      match first.delegate_intent(request, "worker-first", "local-unmetered") {
        Ok(value) => receipts.push(value)
        Err(error) => fail(error)
      }
    })
    group.spawn_bg(() => {
      match
        second.delegate_intent(request, "worker-second", "local-unmetered") {
        Ok(value) => receipts.push(value)
        Err(error) => fail(error)
      }
    })
  })
  assert_eq(receipts.length(), 2)
  assert_eq(receipts[0].worker_run_id, receipts[1].worker_run_id)
  assert_eq(receipts.filter(value => value.receipt.duplicate).length(), 1)
  let winner = receipts[0].worker_run_id
  assert_eq(
    first.worker_learning_input("supervisor-1", winner),
    second.worker_learning_input("supervisor-1", winner),
  )
  let jobs = first.runtime
    .store()
    .list_definitions()
    .filter(value => value.kind == "job.supervisor-worker")
  assert_eq(jobs.length(), 1)
}

///|
async test "runtime locks share aliases release cancellation and leave independent roots free" {
  let root = @fs.tmpdir(prefix="claw-learning-locks-")
  defer @fs.rmdir(root, recursive=true)
  let alias = root + "-alias"
  @fs.symlink(target=root, alias)
  defer @fs.remove(alias)
  let first = learning_runtime(root + "/runtime")
  let same = learning_runtime(alias + "/runtime")
  let independent = learning_runtime(root + "/independent")
  first.with_lock(() => {
    assert_eq(
      @async.with_timeout_opt(5, () => same.with_lock(() => true)),
      None,
    )
    assert_eq(
      @async.with_timeout_opt(1000, () => independent.with_lock(() => true)),
      Some(true),
    )
  })
  assert_eq(
    @async.with_timeout_opt(5, () => first.with_lock(() => @async.sleep(1000))),
    None,
  )
  assert_eq(
    @async.with_timeout_opt(1000, () => same.with_lock(() => true)),
    Some(true),
  )
  first.runtime
  .store()
  .with_store_lock(() => {
    assert_eq(
      @async.with_timeout_opt(5, () => {
        same.runtime.store().with_store_lock(() => true)
      }),
      None,
    )
    assert_eq(
      @async.with_timeout_opt(1000, () => {
        independent.runtime.store().with_store_lock(() => true)
      }),
      Some(true),
    )
  })
  assert_eq(
    @async.with_timeout_opt(5, () => {
      first.runtime.store().with_store_lock(() => @async.sleep(1000))
    }),
    None,
  )
  assert_eq(
    @async.with_timeout_opt(1000, () => {
      same.runtime.store().with_store_lock(() => true)
    }),
    Some(true),
  )
}
