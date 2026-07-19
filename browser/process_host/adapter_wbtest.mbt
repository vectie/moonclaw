///|
fn process_test_action(
  action_id : String,
  target : String,
) -> @browser.BrowserAction {
  @browser.browser_action(
    action_id~,
    session_id="process-session",
    actor=@browser.Agent,
    actor_id="agent-fixture",
    operation=@browser.Click,
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
async test "process host executes typed command and duplicate is deterministic" {
  let cwd = @env.current_dir().unwrap_or(".")
  let state_path = cwd + "/.tmp-browser-host-process-test.json"
  @fs.remove(state_path) catch {
    _ => ()
  }
  let host = ProcessBrowserHost::new(
    executable="node",
    arguments=["browser/process_host/deterministic_fixture.mjs", state_path],
    cwd~,
  )
  let worker = process_test_worker()
  let action = process_test_action(
    "process-action-1", "role=button[name='Run']",
  )
  let command = process_ready_command(worker.prepare(action))
  let first = host.execute(command).unwrap()
  let duplicate = host.execute(command).unwrap()
  assert_eq(first.host_receipt_id, duplicate.host_receipt_id)
  assert_eq(first.before_state_digest, duplicate.before_state_digest)
  assert_eq(first.after_state_digest, duplicate.after_state_digest)
  let receipt = worker.complete(action, command, first)
  assert_true(receipt.accepted())
  assert_eq(receipt.evidence_refs.length(), 0)
  @fs.remove(state_path) catch {
    _ => ()
  }
}

///|
async test "process host crash and timeout never become accepted evidence" {
  let cwd = @env.current_dir().unwrap_or(".")
  let state_path = cwd + "/.tmp-browser-host-process-failure-test.json"
  @fs.remove(state_path) catch {
    _ => ()
  }
  let host = ProcessBrowserHost::new(
    executable="node",
    arguments=["browser/process_host/deterministic_fixture.mjs", state_path],
    cwd~,
  )
  let crash_worker = process_test_worker()
  let crash_action = process_test_action("process-crash", "fixture://crash")
  let crash_command = process_ready_command(crash_worker.prepare(crash_action))
  let crash_error = host.execute(crash_command).unwrap_err()
  let crash_receipt = crash_worker.complete_transport_error(
    crash_action, crash_command, crash_error,
  )
  assert_true(crash_receipt.outcome is Blocked(_))
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
  @fs.remove(state_path) catch {
    _ => ()
  }
}
