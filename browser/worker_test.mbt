///|
fn test_scope() -> @browser.BrowserSessionScope {
  @browser.browser_session_scope(
    session_id="browser-book-r7",
    workspace_id="book-demo",
    book_revision="book-r7",
    code_revision="code-a91",
    run_id="run-7",
    authority_envelope_id="authority-local-preview",
  )
}

///|
fn test_action(
  id : String,
  actor : @browser.BrowserActor,
  operation? : @browser.BrowserOperation = @browser.Click,
  target? : String = "role=button[name='Calculate']",
  code_revision? : String = "code-a91",
  required_effect? : @browser.BrowserEffectClass = @browser.InteractLocalPage,
) -> @browser.BrowserAction {
  @browser.browser_action(
    action_id=id,
    session_id="browser-book-r7",
    actor~,
    actor_id=if actor is @browser.User { "user-1" } else { "agent-1" },
    operation~,
    target~,
    expected_observation="calculator result visible",
    code_revision~,
    authority_envelope_id="authority-local-preview",
    required_effect~,
  )
}

///|
fn ready_command(
  dispatch : @browser.BrowserDispatch,
) -> @browser.BrowserHostCommand raise {
  match dispatch {
    Ready(command) => command
    _ => fail("expected ready browser host command")
  }
}

///|
fn completed_result(
  command : @browser.BrowserHostCommand,
  before? : String = "state-before",
  after? : String = "state-after",
  target_resolved? : Bool = true,
) -> @browser.BrowserHostResult {
  @browser.browser_host_result(
    host_receipt_id="fixture-receipt-" + command.action_id,
    request_id=command.request_id,
    session_id=command.session_id,
    action_id=command.action_id,
    code_revision=command.code_revision,
    authority_envelope_id=command.authority_envelope_id,
    capability_digest=command.capability_digest,
    status=@browser.Completed,
    before_state_digest=before,
    after_state_digest=after,
    screenshot_before_ref="fixture://before/" + command.action_id,
    screenshot_after_ref="fixture://after/" + command.action_id,
    observations=["visible result captured"],
    target_resolved~,
  )
}

///|
test "agent action becomes accepted only after host evidence" {
  let worker = @browser.BrowserWorker::new(test_scope(), action_budget=2)
  assert_true(worker.begin_agent_operation())
  let action = test_action("action-1", @browser.Agent)
  let command = ready_command(worker.prepare(action))
  assert_eq(worker.receipts().length(), 0)
  assert_eq(worker.remaining_actions(), 2)
  let receipt = worker.complete(action, command, completed_result(command))
  assert_true(receipt.accepted())
  assert_eq(receipt.before_state_digest, "state-before")
  assert_eq(receipt.after_state_digest, "state-after")
  assert_eq(receipt.evidence_refs.length(), 2)
  assert_eq(worker.remaining_actions(), 1)
}

///|
test "pause stop and takeover cancel or redirect same visible session" {
  let worker = @browser.BrowserWorker::new(test_scope())
  assert_true(worker.begin_agent_operation())
  let agent_action = test_action("action-agent", @browser.Agent)
  let command = ready_command(worker.prepare(agent_action))
  assert_true(worker.take_over())
  let cancelled = worker.complete(
    agent_action, command, completed_result(command),
  )
  assert_true(cancelled.outcome is Cancelled("agent-control-revoked"))
  let user_action = test_action("action-user", @browser.User)
  let user_command = ready_command(worker.prepare(user_action))
  assert_true(
    worker.complete(
      user_action, user_command, completed_result(user_command),
    ).accepted(),
  )
  assert_true(worker.stop())
  assert_true(
    worker.prepare(test_action("action-stopped", @browser.User))
    is Rejected({ outcome: Blocked("session-stopped"), .. }),
  )
}

///|
test "authority revision secret and default workspace mutation fail closed" {
  let worker = @browser.BrowserWorker::new(test_scope())
  assert_true(worker.begin_agent_operation())
  assert_true(
    worker.prepare(
      test_action(
        "action-save",
        @browser.Agent,
        operation=@browser.CaptureScreenshot,
        required_effect=@browser.SaveWorkspaceEvidence,
      ),
    ) is Rejected({ outcome: Blocked("effect-not-authorized"), .. }),
  )
  assert_true(
    worker.prepare(
      test_action("action-revision", @browser.Agent, code_revision="code-new"),
    ) is Rejected({ outcome: Blocked("code-revision-mismatch"), .. }),
  )
  let secret = @browser.browser_action(
    action_id="action-secret",
    session_id="browser-book-r7",
    actor=@browser.Agent,
    operation=@browser.TypeText,
    target="label=Password",
    value_redacted="actual-secret",
    code_revision="code-a91",
    authority_envelope_id="authority-local-preview",
  )
  assert_true(
    worker.prepare(secret)
    is Rejected({ outcome: Blocked("secret-value-not-redacted"), .. }),
  )
}

///|
test "duplicate host terminal delivery is idempotent" {
  let worker = @browser.BrowserWorker::new(test_scope())
  assert_true(worker.begin_agent_operation())
  let action = test_action("action-duplicate", @browser.Agent)
  let command = ready_command(worker.prepare(action))
  let result = completed_result(command)
  let first = worker.complete(action, command, result)
  let second = worker.complete(action, command, result)
  assert_eq(first.host_receipt_id, second.host_receipt_id)
  assert_eq(worker.receipts().length(), 1)
  assert_true(worker.prepare(action) is Duplicate(_))
}

///|
test "accepted receipt and duplicate guard survive worker restart" {
  let worker = @browser.BrowserWorker::new(test_scope(), action_budget=2)
  assert_true(worker.begin_agent_operation())
  let action = test_action("action-restart", @browser.Agent)
  let command = ready_command(worker.prepare(action))
  let accepted = worker.complete(action, command, completed_result(command))
  assert_true(accepted.accepted())
  let encoded = worker.snapshot().to_json()
  let decoded : @browser.BrowserWorkerSnapshot = @json.from_json(encoded)
  let restored = @browser.BrowserWorker::restore(decoded)
  assert_eq(restored.remaining_actions(), 1)
  assert_eq(restored.receipts().length(), 1)
  assert_true(restored.prepare(action) is Duplicate(_))
}

///|
test "host crash and malformed result cannot create accepted evidence" {
  let worker = @browser.BrowserWorker::new(test_scope())
  assert_true(worker.begin_agent_operation())
  let crashed_action = test_action("action-crash", @browser.Agent)
  let crashed_command = ready_command(worker.prepare(crashed_action))
  let crashed = @browser.browser_host_result(
    host_receipt_id="fixture-crash",
    request_id=crashed_command.request_id,
    session_id=crashed_command.session_id,
    action_id=crashed_command.action_id,
    code_revision=crashed_command.code_revision,
    authority_envelope_id=crashed_command.authority_envelope_id,
    capability_digest=crashed_command.capability_digest,
    status=@browser.Crashed("exit-17"),
    before_state_digest="",
    after_state_digest="",
  )
  assert_true(
    worker.complete(crashed_action, crashed_command, crashed).outcome
    is Blocked("host-crashed:exit-17"),
  )
  let malformed_action = test_action("action-malformed", @browser.Agent)
  let malformed_command = ready_command(worker.prepare(malformed_action))
  assert_true(
    worker.complete(
      malformed_action,
      malformed_command,
      completed_result(malformed_command, before="", after=""),
    ).outcome is Blocked("host-state-digest-missing"),
  )
  let capability_action = test_action("action-capability", @browser.Agent)
  let capability_command = ready_command(worker.prepare(capability_action))
  let wrong_capability = @browser.browser_host_result(
    host_receipt_id="fixture-wrong-capability",
    request_id=capability_command.request_id,
    session_id=capability_command.session_id,
    action_id=capability_command.action_id,
    code_revision=capability_command.code_revision,
    authority_envelope_id=capability_command.authority_envelope_id,
    capability_digest="wrong-capability",
    status=@browser.Completed,
    before_state_digest="before",
    after_state_digest="after",
  )
  assert_true(
    worker.complete(
      capability_action, capability_command, wrong_capability,
    ).outcome is Blocked("host-capability-mismatch"),
  )
}

///|
test "deterministic replay stops on state or semantic divergence" {
  let worker = @browser.BrowserWorker::new(test_scope(), action_budget=4)
  assert_true(worker.begin_agent_operation())
  let source_action = test_action("action-source", @browser.Agent)
  let source_command = ready_command(worker.prepare(source_action))
  let source = worker.complete(
    source_action,
    source_command,
    completed_result(source_command, before="fixture-initial", after="fixture-after"),
  )
  let replay_action = test_action("action-replay", @browser.Replay)
  let replay_command = ready_command(worker.prepare_replay(source, replay_action))
  assert_eq(replay_command.expected_before_digest, "fixture-initial")
  assert_true(
    worker.complete(
      replay_action,
      replay_command,
      completed_result(replay_command, before="unexpected-state"),
    ).outcome is Diverged("before-state-digest-mismatch"),
  )
  let semantic_action = test_action("action-semantic", @browser.Replay)
  let semantic_command = ready_command(
    worker.prepare_replay(source, semantic_action),
  )
  assert_true(
    worker.complete(
      semantic_action,
      semantic_command,
      completed_result(
        semantic_command,
        before="fixture-initial",
        target_resolved=false,
      ),
    ).outcome is Diverged("semantic-target-changed"),
  )
}

///|
test "local verbs map to portable constitutional effect classes" {
  assert_true(
    @browser.browser_operation_effect_class(@browser.Click)
    is InteractLocalPage,
  )
  assert_true(
    @browser.browser_operation_effect_class(@browser.CaptureDiagnostics)
    is InspectVisiblePage,
  )
  assert_true(
    @browser.browser_operation_effect_class(@browser.Navigate)
    is NavigateExternalOrigin,
  )
}

///|
test "origin classes preserve explicit loopback and offline boundary" {
  let local_preview = test_scope()
  assert_true(@browser.browser_scope_policy_issue(local_preview) is None)
  let loopback = @browser.browser_session_scope(
    session_id="loopback-session",
    workspace_id="book-demo",
    book_revision="book-r7",
    code_revision="code-a91",
    run_id="run-7",
    authority_envelope_id="authority-loopback",
    origin_class=@browser.IsolatedLoopback,
    network_policy=@browser.Offline,
    allowed_origins=["http://127.0.0.1:4388"],
  )
  assert_true(@browser.browser_scope_policy_issue(loopback) is None)
  assert_false(@browser.browser_loopback_origin_allowed("http://127.0.0.1.evil.test"))
  assert_false(@browser.browser_loopback_origin_allowed("http://*.localhost:4388"))
  assert_false(@browser.browser_loopback_origin_allowed("http://localhost:4388@evil.test"))
  assert_false(@browser.browser_loopback_origin_allowed("http://localhost:not-a-port"))
  assert_false(@browser.browser_loopback_origin_allowed("http://localhost:4388/path"))
  let wildcard = @browser.browser_session_scope(
    session_id="loopback-session",
    workspace_id="book-demo",
    book_revision="book-r7",
    code_revision="code-a91",
    run_id="run-7",
    authority_envelope_id="authority-loopback",
    origin_class=@browser.IsolatedLoopback,
    allowed_origins=["http://*.localhost:4388"],
  )
  assert_true(@browser.browser_scope_policy_issue(wildcard) is Some(_))
}
