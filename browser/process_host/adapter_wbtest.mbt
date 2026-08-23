///|
fn process_test_action(
  action_id : String,
  target : String,
) -> @browser.BrowserAction {
  @browser.browser_action(
    action_id~,
    session_id="process-session",
    actor=Agent,
    actor_id="agent-fixture",
    operation=Click,
    target~,
    expected_observation="fixture visible state changes",
    code_revision="code-fixture",
    authority_envelope_id="authority-fixture",
  )
}

///|
fn process_test_worker() -> @browser.BrowserWorker {
  let worker = @browser.BrowserWorker::new(
    @browser.browser_session_scope(
      session_id="process-session",
      workspace_id="fixture-book",
      book_revision="book-fixture",
      code_revision="code-fixture",
      run_id="run-fixture",
      authority_envelope_id="authority-fixture",
    ),
  )
  worker.begin_agent_operation() |> ignore()
  worker
}

///|
fn process_ready_command(
  dispatch : @browser.BrowserDispatch,
) -> @browser.BrowserHostCommand raise {
  match dispatch {
    Ready(command) => command
    _ => fail("expected process host command")
  }
}

///|
async test "process host refuses execution without an ExecutionSandbox grant" {
  let host = ProcessBrowserHost::new()
  let worker = process_test_worker()
  let action = process_test_action(
    "process-action-1", "role=button[name='Run']",
  )
  let command = process_ready_command(worker.prepare(action))
  let error = host.execute(command).unwrap_err()
  assert_true(error.contains("ExecutionSandbox grant required"))
  let receipt = worker.complete_transport_error(action, command, error)
  assert_true(receipt.outcome is Blocked(_))
  assert_eq(receipt.evidence_refs.length(), 0)
}

///|
async test "refused process host execution cannot become accepted evidence" {
  let host = ProcessBrowserHost::new()
  let timeout_worker = process_test_worker()
  let timeout_action = process_test_action("process-delay", "fixture://delay")
  let timeout_command = process_ready_command(
    timeout_worker.prepare(timeout_action),
  )
  let timeout_error = host.execute(timeout_command, timeout_ms=50).unwrap_err()
  timeout_worker.pause() |> ignore()
  let timeout_receipt = timeout_worker.complete_transport_error(
    timeout_action, timeout_command, timeout_error,
  )
  assert_true(timeout_receipt.outcome is Cancelled(_))
  assert_eq(timeout_receipt.evidence_refs.length(), 0)
}
