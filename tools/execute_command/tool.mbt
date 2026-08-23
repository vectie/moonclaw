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
    max_output_lines~ : Int,
    receipt~ : @execution_sandbox.MoonFortReceipt,
    audit_id~ : String
  )
  TimedOut(
    command~ : String,
    timeout~ : Int,
    stdout~ : String,
    stderr~ : String,
    max_output_lines~ : Int,
    receipt~ : @execution_sandbox.MoonFortReceipt,
    audit_id~ : String
  )
  Background(command~ : String, job_id~ : Int)
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
fn render_output_artifact(
  artifact : @execution_sandbox.MoonFortCommandOutputArtifactRef,
) -> String {
  "Complete output retained by MoonFort: artifact_id=\{artifact.artifact_id}, sha256=\{artifact.sha256}, size_bytes=\{artifact.size_bytes}, media_type=\{artifact.media_type}, expires_at_ms=\{artifact.expires_at_ms}"
}

///|
pub impl Show for CommandResult with fn output(
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
    Completed(
      command~,
      status~,
      stdout~,
      stderr~,
      max_output_lines~,
      receipt~,
      audit_id~
    ) => {
      let formatted = []
      formatted.push("Command \{command} exited with status \{status}.")
      if !stdout.is_blank() {
        formatted.push(render_output(name="STDOUT", stdout, max_output_lines~))
      }
      if !stderr.is_blank() {
        formatted.push(render_output(name="STDERR", stderr, max_output_lines~))
      }
      if !receipt.changed_paths.is_empty() {
        let paths = receipt.changed_paths.join(", ")
        formatted.push("Changed paths: \{paths}")
      }
      if !receipt.artifacts.is_empty() {
        let artifacts = receipt.artifacts.join(", ")
        formatted.push("Artifacts: \{artifacts}")
      }
      match receipt.output_artifact {
        Some(artifact) => formatted.push(render_output_artifact(artifact))
        None => ()
      }
      formatted.push("Sandbox receipt recorded: audit_id=\{audit_id}.")
      logger.write_string(formatted.join("\n"))
    }
    TimedOut(
      command~,
      timeout~,
      stdout~,
      stderr~,
      max_output_lines~,
      receipt~,
      audit_id~
    ) => {
      let formatted = []
      formatted.push("Command \{command} timed out after \{timeout} ms.")
      if !stdout.is_blank() {
        formatted.push(render_output(name="STDOUT", stdout, max_output_lines~))
      }
      if !stderr.is_blank() {
        formatted.push(render_output(name="STDERR", stderr, max_output_lines~))
      }
      match receipt.output_artifact {
        Some(artifact) => formatted.push(render_output_artifact(artifact))
        None => ()
      }
      formatted.push("Sandbox receipt recorded: audit_id=\{audit_id}.")
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
  cwd : String,
  home? : String,
  approval_scope? : String,
  sandbox_config? : @execution_sandbox.SandboxExecutorConfig,
) -> @tool.Tool[CommandResult] {
  let home = home.unwrap_or(cwd)
  @tool.new(
    description="Execute an shell command with arguments and capture its output.",
    name="execute_command",
    schema~,
    ToolFn(async fn(args) -> @tool.ToolResult[CommandResult] noraise {
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
          @pathx.join(cwd, working_directory)
        }
      } else {
        cwd
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
        token.trim().to_owned()
      } else {
        ""
      }
      let assessment = @security.assess_shell_command(
        command,
        working_directory,
        Some(cwd),
      )
      let scope_key = approval_scope.unwrap_or("local:\{cwd}")
      let security = @security.SecurityRuntime::new(home~, cwd~) catch {
        error =>
          return @tool.error(
            "Failed to initialize command approval runtime: \{error}",
            error~,
          )
      }
      if simulate {
        return @tool.ok(CommandResult::Simulated(assessment~))
      }
      if !assessment.allowed_by_policy {
        return @tool.ok(CommandResult::Blocked(command~, assessment~))
      }
      let mut consumed_approval : @security.ApprovalRecord? = None
      if assessment.requires_approval {
        let target = @security.command_approval_target(assessment)
        if !approval_token.is_blank() {
          let now_ms = @clock.epoch.now().ms().to_int()
          try security.approve_token(approval_token, now_ms) catch {
            _ => ()
          } noraise {
            _ => ()
          }
        }
        let approved_record = security.consume_approval_record(
          "command.execute", target, scope_key,
        ) catch {
          _ => None
        }
        consumed_approval = approved_record
        if approved_record is None {
          let pending = security.matching_pending_approval(
            "command.execute", target, scope_key,
          )
          let record = match pending {
            Some(record) => record
            None => {
              guard sandbox_config is Some(config) else {
                return @tool.error(
                  "MoonFort execution sandbox is not configured; refusing host execution.",
                )
              }
              let plan = @execution_sandbox.make_sandbox_plan(
                config,
                cwd,
                working_directory,
                command,
                timeout.to_int(),
              ) catch {
                error =>
                  return @tool.error(
                    "Failed to prepare MoonFort approval plan: \{error}",
                    error~,
                  )
              }
              let now_ms = @clock.epoch.now().ms().to_int()
              security.request_approval(
                @security.command_approval_token(assessment, now_ms),
                "command.execute",
                target,
                scope_key,
                now_ms,
                context=plan.to_json(),
              ) catch {
                error =>
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
      guard background is false else {
        return @tool.error(
          "Background execution is not supported in this environment.",
        )
      }
      guard sandbox_config is Some(config) else {
        return @tool.error(
          "MoonFort execution sandbox is not configured; refusing host execution.",
        )
      }
      let plan = if assessment.requires_approval {
        guard consumed_approval is Some(record) else {
          return @tool.error("Approved MoonFort execution plan was not found.")
        }
        @execution_sandbox.approved_plan(record) catch {
          error =>
            return @tool.error(
              "Invalid approved MoonFort execution plan: \{error}",
              error~,
            )
        }
      } else {
        @execution_sandbox.make_sandbox_plan(
          config,
          cwd,
          working_directory,
          command,
          timeout.to_int(),
        ) catch {
          error =>
            return @tool.error(
              "Failed to prepare MoonFort execution: \{error}",
              error~,
            )
        }
      }
      @execution_sandbox.validate_approved_plan(
        plan,
        config,
        @fsx.resolve(cwd),
        @fsx.resolve(working_directory),
        command,
      ) catch {
        error =>
          return @tool.error(
            "MoonFort approval validation failed: \{error}",
            error~,
          )
      }
      let receipt = @execution_sandbox.invoke_moonfort(config, plan) catch {
        error =>
          return @tool.error(
            "MoonFort execution failed closed: \{error}",
            error~,
          )
      }
      let audit_path = @execution_sandbox.persist_sandbox_audit(
        config, plan, receipt,
      ) catch {
        error =>
          return @tool.error(
            "MoonFort receipt persistence failed: \{error}",
            error~,
          )
      }
      ignore(audit_path)
      let audit_id = receipt.run_id
      match receipt.status {
        @execution_sandbox.Exited => {
          guard receipt.exit_code is Some(status) else {
            return @tool.error("MoonFort exited receipt omitted exit_code.")
          }
          @tool.ok(
            Completed(
              command~,
              status~,
              stdout=receipt.output,
              stderr="",
              max_output_lines~,
              receipt~,
              audit_id~,
            ),
          )
        }
        @execution_sandbox.Killed if receipt.limit_reason
          is Some("wall-clock-limit") =>
          @tool.ok(
            TimedOut(
              command~,
              timeout=plan.grant.limits.wall_clock_ms,
              stdout=receipt.output,
              stderr="",
              max_output_lines~,
              receipt~,
              audit_id~,
            ),
          )
        @execution_sandbox.Killed => {
          let reason = receipt.limit_reason.unwrap_or("unspecified limit")
          @tool.error(
            "MoonFort killed the command at a resource boundary: \{reason}",
          )
        }
        @execution_sandbox.Failed => {
          let reason = receipt.denial_reason.unwrap_or("unspecified failure")
          @tool.error("MoonFort reported execution failure: \{reason}")
        }
        @execution_sandbox.Created | @execution_sandbox.Running =>
          @tool.error("MoonFort returned a non-terminal receipt.")
      }
    }),
  )
}
