///|
test "getpid" {
  ignore(@spawn.getpid())
  ignore(@spawn.getppid())
}

///|
async test "Manager::spawn" (t : @test.Test) {
  @mock.run(t, mock => {
    let manager = @spawn.Manager::new(cwd=mock.cwd.path())
    mock.group.spawn_bg(() => manager.start(), no_wait=true)
    let process = manager.spawn("sleep", ["2"])
    json_inspect(process.pid, content=0)
  })
}

///|
async test "Manager::wait" (t : @test.Test) {
  @mock.run(t, mock => {
    let manager = @spawn.Manager::new(cwd=mock.cwd.path())
    mock.group.spawn_bg(() => manager.start(), no_wait=true)
    let process = manager.spawn("sleep", ["2"])
    let status = process.wait()
    json_inspect(status, content=0)
  })
}

///|
async test "spawn/env" (t : @test.Test) {
  @mock.run(t, _ => {
    let process = @spawn.spawn("sh", ["-c", "echo $TEST_ENV_VAR"], env={
      "TEST_ENV_VAR": "hello_world",
    })
    json_inspect(process.status, content=0)
    json_inspect(process.stdout, content="hello_world\n")
  })
}

///|
async test "redirect-stdin" (t : @test.Test) {
  @mock.run(t, _ => {
    let process = @spawn.spawn("cat", [], stdin="Hello, World!\n")
    json_inspect(process.status, content=0)
    inspect(
      process.stdout,
      content=(
        #|Hello, World!
        #|
      ),
    )
  })
}

///|
async test "spawn/failed" (t : @test.Test) {
  @mock.run(t, _ => {
    let process = @spawn.spawn("sh", ["-c", "exit 42"])
    json_inspect(
      (Ok(process.check()) catch { error => Err(error) })
      .to_json()
      .transform(@json.Replacer::exclude(["elapsed"])),
      content={
        "Err": [
          "Failed",
          {
            "exec": "sh",
            "args": ["-c", "exit 42"],
            "status": 42,
            "stdout": "",
            "stderr": "",
          },
        ],
      },
    )
  })
}

///|
async test "spawn timeout permits process cleanup traps" (t : @test.Test) {
  @mock.run(t, _ => {
    try
      @spawn.spawn(
        "sh",
        [
          "-c", "trap 'printf cleanup-ran >&2; exit 0' TERM; while :; do :; done",
        ],
        timeout=20,
      )
    catch {
      @spawn.TimedOut(stderr~, ..) => inspect(stderr, content="cleanup-ran")
      _ => fail("unexpected process error")
    } noraise {
      _ => fail("expected process timeout")
    }
  })
}
