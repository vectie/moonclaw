///|
async test "Manager::spawn" (t : @test.Test) {
  @mock.run(t, mock => {
    let manager = @job.Manager::new(cwd=mock.cwd.path())
    mock.group.spawn_bg(() => manager.start(), no_wait=true)
    let job = manager.spawn(name="sleep", command="sleep 2")
    json_inspect(job.status(), content=null)
    json_inspect(job.id, content=0)
    json_inspect(job.command, content="sleep 2")
    json_inspect(mock.json(job.cwd), content="(mock:cwd)")
    json_inspect(
      mock.json(job.stdout),
      content="(mock:cwd)/.moonsuite/products/moonclaw/jobs/processes/0/stdout",
    )
    json_inspect(
      mock.json(job.stderr),
      content="(mock:cwd)/.moonsuite/products/moonclaw/jobs/processes/0/stderr",
    )
  })
}

///|
async test "Manager::wait" (t : @test.Test) {
  @mock.run(t, mock => {
    let manager = @job.Manager::new(cwd=mock.cwd.path())
    mock.group.spawn_bg(() => manager.start(), no_wait=true)
    let job = manager.spawn(name="sleep", command="sleep 2")
    json_inspect(job.status(), content=null)
    let _ = job.wait()
    json_inspect(job.status(), content=[0])
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
