///|
test "daemon child model arguments preserve exact selector and separate workspace" {
  assert_eq(
    @trusted_host_process.daemon_child_model_arguments(
      Some("moongate/catalog/id"),
      Some("/suite/books/selected"),
    ),
    [
      "--model", "moongate/catalog/id", "--model-workspace", "/suite/books/selected",
    ],
  )
  assert_eq(
    @trusted_host_process.daemon_child_model_arguments(
      Some("codex/gpt-5.4"),
      None,
    ),
    ["--model", "codex/gpt-5.4"],
  )
  for invalid in ["", "/", "relative", "/tmp/\u0000book"] {
    try
      @trusted_host_process.daemon_child_model_arguments(
        Some("moongate/id"),
        Some(invalid),
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid workspace to fail")
    }
  }
}
