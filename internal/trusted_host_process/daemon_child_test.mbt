///|
async test "daemon child manager runs only the typed server operation" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let root = @fs.realpath(mock.cwd.path())
    let manager = @trusted_host_process.DaemonChildManager::new(
      cwd=root,
      executable="/usr/bin/true",
      home=root,
    )
    mock.group.spawn_bg(() => manager.start(), no_wait=true)
    let child = manager.spawn_server(
      cwd=root,
      name="test task",
      model_selector="test-model",
      register_id="00000000-0000-0000-0000-000000000001",
      register_port=4199,
      register_token="a".repeat(72),
    )
    inspect(child.wait(), content="0")
    assert_false(child.pid_string().is_blank())
  })
}

///|
async test "daemon child manager rejects caller-selected relative executable" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let root = @fs.realpath(mock.cwd.path())
    let manager = @trusted_host_process.DaemonChildManager::new(
      cwd=root,
      executable="true",
      home=root,
    )
    try
      manager.spawn_server(
        cwd=root,
        register_id="00000000-0000-0000-0000-000000000001",
        register_port=4199,
        register_token="a".repeat(72),
      )
    catch {
      @trusted_host_process.InvalidParameter(message) =>
        inspect(
          message,
          content="daemon child executable must be an absolute non-root path",
        )
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected a relative executable to be rejected")
    }
  })
}

///|
async test "daemon child manager rejects invalid registration data before spawn" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let root = @fs.realpath(mock.cwd.path())
    let manager = @trusted_host_process.DaemonChildManager::new(
      cwd=root,
      executable="/usr/bin/true",
      home=root,
    )
    try
      manager.spawn_server(
        cwd=root,
        register_id="valid-id",
        register_port=0,
        register_token="a".repeat(72),
      )
    catch {
      @trusted_host_process.InvalidParameter(message) =>
        inspect(message, content="invalid daemon child register port")
      error => fail("unexpected error: \{error}")
    } noraise {
      _ => fail("expected an invalid port to be rejected")
    }
  })
}
