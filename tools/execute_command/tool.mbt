///|
pub struct CommandOutput {
  text : String
  truncated_lines : Int
  original_lines : Int
} derive(ToJson, @json.FromJson)

///|
pub enum CommandResult {
  Simulated(assessment~ : @security.CommandAssessment)
  ApprovalRequired(
    command~ : String,
    assessment~ : @security.CommandAssessment,
    token~ : String
  )
  Blocked(command~ : String, assessment~ : @security.CommandAssessment)
  Completed(
    command~ : String,
    status~ : Int,
    stdout~ : String,
    stderr~ : String,
    max_output_lines~ : Int
  )
  TimedOut(
    command~ : String,
    timeout~ : Int,
    stdout~ : String,
    stderr~ : String,
    max_output_lines~ : Int
  )
  Background(command~ : String, job_id~ : @job.Id)
} derive(@json.FromJson, ToJson)

///|
fn render_output(
  name~ : String,
  output : String,
  max_output_lines~ : Int,
) -> String {
  let formatted = StringBuilder::new()
  let lines = output.split("\n").collect()
  if lines.length() >= max_output_lines {
    formatted.write_string(
      "=== \{name} (first \{max_output_lines} of \{lines.length()} lines) ===\n",
    )
    formatted.write_string(lines[:max_output_lines].join("\n"))
    formatted.write_string(
      "\n... (truncated, try using redirection to pipe output to a file) ...",
    )
  } else {
    formatted.write_string("=== \{name} (\{lines.length()} lines) ===\n")
    formatted.write_string(output)
  }
  formatted.to_string()
}

///|
pub impl Show for CommandResult with output(
  self : CommandResult,
  logger : &Logger,
) -> Unit {
  match self {
    Simulated(assessment~) => {
      let reasons = assessment.reasons.join("; ")
      let effects = assessment.predicted_effects.join(", ")
      logger.write_string(
        "Simulation only. Risk=\{assessment.risk_level}, intent=\{assessment.intent}, reasons=\{reasons}, effects=\{effects}.",
      )
    }
    ApprovalRequired(command~, assessment~, token~) => {
      ignore(command)
      logger.write_string(
        @security.render_command_approval_required(assessment, token~),
      )
    }
    Blocked(command~, assessment~) => {
      let reasons = assessment.reasons.join("; ")
      logger.write_string(
        "Command \{command} is blocked by sandbox policy. Reasons: \{reasons}.",
      )
    }
    Completed(command~, status~, stdout~, stderr~, max_output_lines~) => {
      let formatted = []
      formatted.push("Command \{command} exited with status \{status}.")
      if !stdout.is_blank() {
        formatted.push(render_output(name="STDOUT", stdout, max_output_lines~))
      }
      if !stderr.is_blank() {
        formatted.push(render_output(name="STDERR", stderr, max_output_lines~))
      }
      logger.write_string(formatted.join("\n"))
    }
    TimedOut(command~, timeout~, stdout~, stderr~, max_output_lines~) => {
      let formatted = []
      formatted.push("Command \{command} timed out after \{timeout} seconds.")
      if !stdout.is_blank() {
        formatted.push(render_output(name="STDOUT", stdout, max_output_lines~))
      }
      if !stderr.is_blank() {
        formatted.push(render_output(name="STDERR", stderr, max_output_lines~))
      }
      logger.write_string(formatted.join("\n"))
    }
    Background(command~, job_id~) =>
      logger.write_string(
        "Command \{command} started in background with Job ID \{job_id}",
      )
  }
}

///|
pub fn new(
  ctx : @job.Manager,
  approval_scope? : String,
) -> @tool.Tool[CommandResult] {
  @tool.new(
    description="Execute an shell command with arguments and capture its output.",
    name="execute_command",
    schema~,
    @tool.ToolFn(async fn(args) -> @tool.ToolResult[CommandResult] noraise {
      guard args is { "command": String(command), .. } else {
        return @tool.error("Error: 'command' parameters is required")
      }
      let timeout = if args is { "timeout": timeout, .. } {
        let timeout = match timeout {
          Number(timeout, ..) => timeout
          _ => return @tool.error("'timeout' must be a number")
        }
        if timeout <= 0 {
          return @tool.error("'timeout' must be a positive integer")
        }
        timeout
      } else {
        600_000
      }
      let max_output_lines = if args
        is { "max_output_lines": Number(max_output_lines, ..), .. } {
        if max_output_lines <= 0 {
          return @tool.error("'max_output_lines' must be a positive integer")
        }
        max_output_lines.to_int()
      } else {
        100
      }
      let working_directory = if args
        is { "working_directory": String(working_directory), .. } {
        if @pathx.is_absolute(working_directory) {
          working_directory
        } else {
          @pathx.join(ctx.cwd, working_directory)
        }
      } else {
        ctx.cwd
      }
      let background = if args is { "background": background, .. } {
        match background {
          True => true
          False => false
          _ => return @tool.error("'background' must be a boolean")
        }
      } else {
        false
      }
      let simulate = if args is { "simulate": simulate, .. } {
        match simulate {
          True => true
          False => false
          _ => return @tool.error("'simulate' must be a boolean")
        }
      } else {
        false
      }
      let approval_token = if args is { "approval_token": String(token), .. } {
        token.trim().to_string()
      } else {
        ""
      }
      let assessment = @security.assess_shell_command(
        command,
        working_directory,
        Some(ctx.cwd),
      )
      let scope_key = approval_scope.unwrap_or("local:\{ctx.cwd}")
      let security_result : Result[@security.SecurityRuntime, Error] = try? @security.SecurityRuntime::new(
        home=ctx.home,
        cwd=ctx.cwd,
      )
      let security = match security_result {
        Ok(runtime) => runtime
        Err(error) =>
          return @tool.error(
            "Failed to initialize command approval runtime: \{error}",
            error~,
          )
      }
      // FIXME: enable background execution when supported
      guard background is false else {
        @tool.error(
          "Background execution is not supported in this environment.",
        )
      }
      if simulate {
        return @tool.ok(CommandResult::Simulated(assessment~))
      }
      if !assessment.allowed_by_policy {
        return @tool.ok(CommandResult::Blocked(command~, assessment~))
      }
      if assessment.requires_approval {
        let target = @security.command_approval_target(assessment)
        if !approval_token.is_blank() {
          let now_ms = @clock.epoch.now().ms().to_int()
          let _ : Result[@security.ApprovalRecord?, Error] = try? security.approve_token(
            approval_token, now_ms,
          )
        }
        let approved_result : Result[Bool, Error] = try? security.consume_approval(
          "command.execute", target, scope_key,
        )
        let approved = approved_result.unwrap_or(false)
        if !approved {
          let pending = security.matching_pending_approval(
            "command.execute", target, scope_key,
          )
          let record = match pending {
            Some(record) => record
            None => {
              let now_ms = @clock.epoch.now().ms().to_int()
              let request_result : Result[@security.ApprovalRecord, Error] = try? security.request_approval(
                @security.command_approval_token(assessment, now_ms),
                "command.execute",
                target,
                scope_key,
                now_ms,
              )
              match request_result {
                Ok(record) => record
                Err(error) =>
                  return @tool.error(
                    "Failed to create approval request for command '\{command}': \{error}",
                    error~,
                  )
              }
            }
          }
          return @tool.ok(
            CommandResult::ApprovalRequired(
              command~,
              assessment~,
              token=record.token,
            ),
          )
        }
      }
      if background {
        let job = ctx.spawn(name=command, command~) catch {
          error =>
            return @tool.error(
              "Failed to start background job for command '\{command}': \{error}",
            )
        }
        @tool.ok(CommandResult::Background(command~, job_id=job.id))
      } else {
        let timeout = timeout.to_int()
        let process = @spawn.spawn(
          "sh",
          ["-c", command],
          timeout~,
          cwd=working_directory,
        ) catch {
          @spawn.TimedOut(timeout~, stdout~, stderr~) =>
            return @tool.ok(
              CommandResult::TimedOut(
                command~,
                timeout~,
                stdout~,
                stderr~,
                max_output_lines~,
              ),
            )
          error =>
            return @tool.error(
              "Failed to execute command '\{command}': \{error}",
              error~,
            )
        }
        return @tool.ok(
          CommandResult::Completed(
            command~,
            status=process.status,
            stdout=process.stdout,
            stderr=process.stderr,
            max_output_lines~,
          ),
        )
      }
    }),
  )
}
