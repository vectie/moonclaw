///|
async test "timeout" (t : @test.Test) {
  @mock.run(t, mock => {
    @async.with_task_group(_ => {
      let tool = @execute_command.new(@job.Manager::new(cwd=mock.cwd.path()))
      json_inspect(tool.call({ "command": "sleep 5", "timeout": 1000 }), content=[
        "Ok",
        [
          "TimedOut",
          {
            "command": "sleep 5",
            "timeout": 1000,
            "stdout": "",
            "stderr": "",
            "max_output_lines": 100,
          },
        ],
      ])
    })
  })
}

///|
async test "cat" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({ "file.txt": "hello world" })
    let tool = @execute_command.new(@job.Manager::new(cwd=mock.cwd.path()))
    let result = tool.call({ "command": "cat file.txt", "timeout": 5000 })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(
      output,
      content=(
        #|Command cat file.txt exited with status 0.
        #|=== STDOUT (1 lines) ===
        #|hello world
      ),
    )
  })
}

///|
async test "output-overflow" (t : @test.Test) {
  @mock.run(t, mock => {
    let lines = []
    for i = 0; i < 100; i = i + 1 {
      lines.push("hello")
    }
    mock.add_json_tree({ "file.txt": lines.join("\n") })
    let tool = @execute_command.new(@job.Manager::new(cwd=mock.cwd.path()))
    let result = tool.call({
      "command": "cat file.txt",
      "timeout": 5000,
      "max_output_lines": 5,
    })
    // For output-overflow case, we can't predict the exact UUID in the output_file path
    // So we'll check the structure and key fields, allowing flexibility for the UUID
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(
      output,
      content=(
        #|Command cat file.txt exited with status 0.
        #|=== STDOUT (first 5 of 100 lines) ===
        #|hello
        #|hello
        #|hello
        #|hello
        #|hello
        #|... (truncated, try using redirection to pipe output to a file) ...
      ),
    )
  })
}

///|
async test "cd" (t : @test.Test) {
  @mock.run(t, mock => {
    mock.add_json_tree({
      "file.txt": "hello world",
      "subdir": { "file.txt": "hello from subdir" },
    })
    let tool = @execute_command.new(@job.Manager::new(cwd=mock.cwd.path()))
    let result = tool.call({ "command": "cat file.txt", "timeout": 5000 })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    json_inspect(output, content=[
      "Completed",
      {
        "command": "cat file.txt",
        "status": 0,
        "stdout": "hello world",
        "stderr": "",
        "max_output_lines": 100,
      },
    ])
    let tool = @execute_command.new(@job.Manager::new(cwd=mock.cwd.path()))
    let result = tool.call({
      "command": "cd subdir && cat file.txt",
      "timeout": 5000,
    })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    json_inspect(output, content=[
      "Completed",
      {
        "command": "cd subdir && cat file.txt",
        "status": 0,
        "stdout": "hello from subdir",
        "stderr": "",
        "max_output_lines": 100,
      },
    ])
  })
}

///|
async test "simulate returns command assessment without executing" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let tool = @execute_command.new(@job.Manager::new(cwd=mock.cwd.path()))
    let result = tool.call({
      "command": "echo hello > out.txt",
      "simulate": true,
    })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(
      output,
      content=(
        #|Simulation only. Risk=High, intent=Shell, reasons=Command may modify files., effects=write-files.
      ),
    )
    inspect(
      @fsx.exists(@pathx.join(mock.cwd.path(), "out.txt")),
      content="false",
    )
  })
}

///|
async test "high risk command requires explicit approval" (t : @test.Test) {
  @mock.run(t, mock => {
    let tool = @execute_command.new(@job.Manager::new(cwd=mock.cwd.path()))
    let result = tool.call({ "command": "echo hello > out.txt" })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    let rendered = output.to_string()
    assert_true(rendered.contains("Approval required for command execution."))
    assert_true(rendered.contains("Risk: High"))
    assert_true(rendered.contains("Command: `echo hello > out.txt`"))
    let security = @security.SecurityRuntime::new(
      home=mock.cwd.path(),
      cwd=mock.cwd.path(),
    )
    inspect(
      security.list_pending_approvals("local:\{mock.cwd.path()}").length(),
      content="1",
    )
    inspect(
      @fsx.exists(@pathx.join(mock.cwd.path(), "out.txt")),
      content="false",
    )
  })
}

///|
async test "high risk command records approval under injected scope" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let tool = @execute_command.new(
      @job.Manager::new(cwd=mock.cwd.path()),
      approval_scope="feishu:default:chat-1",
    )
    let result = tool.call({ "command": "echo hello > out.txt" })
    guard result is Ok(_) else { fail("Expected Ok result but got: \{result}") }
    let security = @security.SecurityRuntime::new(
      home=mock.cwd.path(),
      cwd=mock.cwd.path(),
    )
    inspect(
      security.list_pending_approvals("feishu:default:chat-1").length(),
      content="1",
    )
    inspect(
      security.list_pending_approvals("local:\{mock.cwd.path()}").length(),
      content="0",
    )
  })
}

///|
async test "approved high risk command executes" (t : @test.Test) {
  @mock.run(t, mock => {
    let tool = @execute_command.new(@job.Manager::new(cwd=mock.cwd.path()))
    let first = tool.call({ "command": "echo hello > out.txt" })
    guard first is Ok(ApprovalRequired(command~, assessment~, token~)) else {
      fail("Expected approval-required result but got: \{first}")
    }
    ignore(command)
    ignore(assessment)
    let result = tool.call({
      "command": "echo hello > out.txt",
      "approval_token": token,
    })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(
      output,
      content=(
        #|Command echo hello > out.txt exited with status 0.
      ),
    )
    inspect(
      @fsx.exists(@pathx.join(mock.cwd.path(), "out.txt")),
      content="true",
    )
  })
}

///|
async test "pre-approved high risk command executes without resending token" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let tool = @execute_command.new(
      @job.Manager::new(cwd=mock.cwd.path()),
      approval_scope="feishu:default:chat-1",
    )
    let first = tool.call({ "command": "echo hello > out.txt" })
    guard first is Ok(ApprovalRequired(command~, assessment~, token~)) else {
      fail("Expected approval-required result but got: \{first}")
    }
    ignore(command)
    let security = @security.SecurityRuntime::new(
      home=mock.cwd.path(),
      cwd=mock.cwd.path(),
    )
    ignore(security.approve_token(token, 11))
    let result = tool.call({ "command": assessment.command })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(
      output,
      content=(
        #|Command echo hello > out.txt exited with status 0.
      ),
    )
    inspect(
      security.list_pending_approvals("feishu:default:chat-1").length(),
      content="0",
    )
  })
}

///|
async test "blocked command is denied even with approval flag" (t : @test.Test) {
  @mock.run(t, mock => {
    let tool = @execute_command.new(@job.Manager::new(cwd=mock.cwd.path()))
    let result = tool.call({
      "command": "sudo rm -rf /",
      "approval_token": "ignored",
    })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    inspect(
      output,
      content=(
        #|Command sudo rm -rf / is blocked by sandbox policy. Reasons: Privilege escalation requested.; Host-destructive command pattern detected.; Command may modify files..
      ),
    )
  })
}

///|
/// FIXME: enable background execution when supported
#cfg(false)
async test "background" (t : @test.Test) {
  @mock.run(t, mock => {
    let manager = @job.Manager::new(cwd=mock.cwd.path())
    mock.group.spawn_bg(() => manager.start(), no_wait=true)
    let tool = @execute_command.new(manager)
    let result = tool.call({ "command": "sleep 2", "background": true })
    guard result is Ok(output) else {
      fail("Expected Ok result but got: \{result}")
    }
    json_inspect(output, content=[
      "Background",
      { "command": "sleep 2", "job_id": 0 },
    ])
  })
}
