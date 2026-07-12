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
) -> @browser.BrowserAction {
  @browser.browser_action(
    action_id=id,
    session_id="browser-book-r7",
    actor~,
    operation=@browser.Click,
    target="role=button[name='Calculate']",
    code_revision="code-a91",
    authority_envelope_id="authority-local-preview",
  )
}

///|
test "agent operation is visible, pausable, and transferable to user" {
  let worker = @browser.BrowserWorker::new(test_scope(), action_budget=2)
  assert_true(worker.status() is Ready)
  assert_true(worker.begin_agent_operation())
  assert_true(worker.status() is AgentOperating)
  assert_true(worker.pause())
  assert_true(worker.status() is Paused)
  assert_true(worker.take_over())
  assert_true(worker.status() is UserControl)
  let receipt = worker.execute(
    test_action("action-user", @browser.User),
    target_stable=true,
    observations=["calculator result visible"],
  )
  assert_true(receipt.accepted())
  assert_true(worker.return_to_agent())
  assert_true(worker.status() is Paused)
}

///|
test "worker fails closed on mismatched scope, secret, and budget" {
  let worker = @browser.BrowserWorker::new(test_scope(), action_budget=1)
  assert_true(worker.begin_agent_operation())
  let first = worker.execute(
    test_action("action-1", @browser.Agent),
    target_stable=true,
  )
  assert_true(first.accepted())
  let exhausted = worker.execute(
    test_action("action-2", @browser.Agent),
    target_stable=true,
  )
  assert_true(exhausted.outcome is Blocked("action-budget-exhausted"))
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
    worker.execute(secret, target_stable=true).outcome
    is Blocked("secret-value-not-redacted"),
  )
}

///|
test "replay stops on revision, operation, or semantic target divergence" {
  let worker = @browser.BrowserWorker::new(test_scope(), action_budget=4)
  assert_true(worker.begin_agent_operation())
  let first = worker.execute(
    test_action("action-1", @browser.Agent),
    target_stable=true,
  )
  let replay = test_action("action-replay", @browser.Replay)
  assert_true(
    worker.replay(first, replay, target_stable=false).outcome
    is Diverged("semantic-target-changed"),
  )
  let wrong_revision = @browser.browser_action(
    action_id="action-wrong-revision",
    session_id="browser-book-r7",
    actor=@browser.Replay,
    operation=@browser.Click,
    target="role=button[name='Calculate']",
    code_revision="code-new",
    authority_envelope_id="authority-local-preview",
  )
  assert_true(
    worker.replay(first, wrong_revision, target_stable=true).outcome
    is Diverged("replay-lineage-mismatch"),
  )
  assert_true(worker.stop())
  assert_true(
    worker.execute(replay, target_stable=true).outcome
    is Blocked("session-stopped"),
  )
}

///|
test "local action verbs map to portable constitutional effect classes" {
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
