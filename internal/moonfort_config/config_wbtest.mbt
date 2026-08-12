///|
test "sandbox executor config parser rejects malformed input without reflection" {
  try parse_sandbox_executor_config("secret-token-not-json") catch {
    error => {
      let message = error.to_string()
      inspect(message.contains("malformed"), content="true")
      inspect(message.contains("secret-token-not-json"), content="false")
    }
  } noraise {
    _ => fail("expected malformed config refusal")
  }
}

///|
test "sandbox executor config parser accepts the typed operator contract" {
  let expected = @execution_sandbox.local_sandbox_executor_config(
    "/opt/moonfort/bin/grant-publisher", "/opt/moonfort/bin/executor", "/etc/moonfort/executor.json",
    "/var/lib/moonclaw/receipts", "primary",
  )
  let config = parse_sandbox_executor_config(expected.to_json().stringify())
  inspect(config.workspace_id, content="primary")
  assert_eq(config.allowed_commands, ["shell-compat"])
  inspect(config.limits.processes, content="256")
}
