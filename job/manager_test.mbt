///|
async test "Manager::spawn fails closed without an execution sandbox" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let manager = @job.Manager::new(cwd=mock.cwd.path())
    let result : Result[String, Error] = Ok(
      {
        ignore(manager.spawn(name="sleep", command="sleep 2"))
        "executed"
      },
    ) catch {
      error => Err(error)
    }
    inspect(
      match result {
        Ok(value) => value
        Err(@job.ExecutionSandboxRequired(command)) => "sandbox:\{command}"
        Err(_) => "other"
      },
      content="sandbox:sleep 2",
    )
    json_inspect(manager.list().length(), content=0)
  })
}

///|
async test "Manager::start has no raw host-process runtime" (t : @test.Test) {
  @mock.run(t, mock => {
    let manager = @job.Manager::new(cwd=mock.cwd.path())
    manager.start()
    json_inspect(manager.list().length(), content=0)
  })
}

///|
async test "Manager::spawn requires approval for high risk command" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let manager = @job.Manager::new(cwd=mock.cwd.path())
    let result : Result[String, Error] = Ok(
      {
        ignore(manager.spawn(name="write", command="echo hello > out.txt"))
        "ok"
      },
    ) catch {
      error => Err(error)
    }
    inspect(
      match result {
        Ok(value) => value
        Err(@job.CommandApprovalRequired(assessment)) =>
          "approval:\{assessment.risk_level}:\{assessment.command}"
        Err(_) => "other"
      },
      content="approval:High:echo hello > out.txt",
    )
  })
}

///|
async test "Manager::spawn blocks destructive command" (t : @test.Test) {
  @mock.run(t, mock => {
    let manager = @job.Manager::new(cwd=mock.cwd.path())
    let result : Result[String, Error] = Ok(
      {
        ignore(manager.spawn(name="destroy", command="sudo rm -rf /"))
        "ok"
      },
    ) catch {
      error => Err(error)
    }
    inspect(
      match result {
        Ok(value) => value
        Err(@job.CommandBlocked(assessment)) =>
          "blocked:\{assessment.risk_level}:\{assessment.command}"
        Err(_) => "other"
      },
      content="blocked:Blocked:sudo rm -rf /",
    )
  })
}
