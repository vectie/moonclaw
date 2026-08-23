///|
/// One generic tool invocation in an installed MoonPack workflow.
///
/// `config` is opaque to MoonClaw. The pack tool handler receives it together
/// with the validated tool binding in the compiled workflow step.
pub(all) struct PackWorkflowToolStep {
  id : String
  tool_id : String
  config : Json
  retry_policy : @job.RetryPolicy?
} derive(Debug, ToJson, FromJson)

///|
/// Machine-readable workflow contract accepted by MoonClaw's pack bridge.
pub(all) struct PackWorkflowDeclaration {
  contract : String
  pack_id : String
  product_id : String
  id : String
  version : String
  steps : Array[PackWorkflowToolStep]
  output_bindings : Array[String]
} derive(Debug, ToJson, FromJson)

///|
/// Native MoonClaw records produced from one pack workflow declaration.
pub(all) struct PackJobCompilation {
  definition : @job.JobDefinition
  workflow : @job.WorkflowDefinition
} derive(Debug, ToJson, FromJson)

///|
/// Durable records created by `intake_workflow_run`.
pub(all) struct PackJobIntake {
  definition : @job.JobDefinition
  workflow : @job.WorkflowDefinition
  run : @job.JobRun
} derive(Debug, ToJson, FromJson)

///|
pub fn decode_workflow_declaration(
  text : String,
) -> PackWorkflowDeclaration raise {
  @json.from_json(@json.parse(text))
}

///|
fn require_pack_projection(
  projection : @host.HostActivationProjection,
) -> Unit raise {
  if projection.contract != "moonsuite.pack-host-activation.v1" {
    fail("unsupported pack host projection")
  }
  if !@pack.safe_identifier(projection.pack_id) ||
    !@pack.safe_identifier(projection.product_id) ||
    !@pack.safe_identifier(projection.version) {
    fail("pack projection identity is unsafe or incomplete")
  }
}

///|
fn require_workflow_declaration(
  declaration : PackWorkflowDeclaration,
) -> Unit raise {
  if declaration.contract != "moonsuite.pack-workflow.v1" {
    fail("unsupported pack workflow contract")
  }
  if declaration.pack_id.trim().is_blank() ||
    declaration.product_id.trim().is_blank() {
    fail("pack workflow ownership is incomplete")
  }
  if !@pack.safe_identifier(declaration.id) ||
    !@pack.safe_identifier(declaration.version) {
    fail("pack workflow id or version is unsafe or incomplete")
  }
  if declaration.steps.is_empty() {
    fail("pack workflow must declare at least one tool step")
  }
  let step_ids : Map[String, Unit] = Map([])
  for step in declaration.steps {
    if !@pack.safe_identifier(step.id) {
      fail("unsafe pack workflow step id: " + step.id)
    }
    if step_ids.contains(step.id) {
      fail("duplicate pack workflow step id: " + step.id)
    }
    step_ids.set(step.id, ())
    if step.tool_id.trim().is_blank() {
      fail("pack workflow step has no tool id: " + step.id)
    }
    match step.retry_policy {
      Some(policy) if policy.max_attempts < 1 =>
        fail("pack workflow step retry attempts must be positive: " + step.id)
      Some({ backoff_ms: Some(backoff_ms), .. }) if backoff_ms < 0 =>
        fail("pack workflow step retry backoff cannot be negative: " + step.id)
      _ => ()
    }
  }
  let outputs : Map[String, Unit] = Map([])
  for output in declaration.output_bindings {
    if output.trim().is_blank() {
      fail("pack workflow output binding cannot be blank")
    }
    if outputs.contains(output) {
      fail("duplicate pack workflow output binding: " + output)
    }
    if !step_ids.contains(output) {
      fail("pack workflow output binding references unknown step: " + output)
    }
    outputs.set(output, ())
  }
}

///|
fn workflow_schedule(
  projection : @host.HostActivationProjection,
  workflow_id : String,
  schedule_id : String?,
) -> @pack.ScheduleDeclaration? raise {
  match schedule_id {
    None => None
    Some(schedule_id) => {
      let selected = projection.schedules.filter(schedule => {
        schedule.id == schedule_id
      })
      guard selected is [schedule] else {
        fail("unknown or duplicate pack schedule: " + schedule_id)
      }
      if schedule.workflow_id != workflow_id {
        fail(
          "pack schedule " +
          schedule_id +
          " targets workflow " +
          schedule.workflow_id,
        )
      }
      if !@pack.safe_identifier(schedule.id) ||
        schedule.cadence.trim().is_blank() ||
        schedule.timezone.trim().is_blank() {
        fail("pack schedule is unsafe or incomplete: " + schedule_id)
      }
      Some(schedule)
    }
  }
}

///|
fn compiled_workflow_id(
  projection : @host.HostActivationProjection,
  declaration : PackWorkflowDeclaration,
) -> String {
  "pack.\{projection.pack_id}.v\{projection.version}.workflow.\{declaration.id}.v\{declaration.version}"
}

///|
fn compiled_job_id(
  projection : @host.HostActivationProjection,
  declaration : PackWorkflowDeclaration,
  schedule : @pack.ScheduleDeclaration?,
) -> String {
  let base = "pack.\{projection.pack_id}.v\{projection.version}.job.\{declaration.id}.v\{declaration.version}"
  match schedule {
    Some(schedule) => "\{base}.schedule.\{schedule.id}"
    None => base
  }
}

///|
fn compiled_step_config(
  projection : @host.HostActivationProjection,
  declaration : PackWorkflowDeclaration,
  step : PackWorkflowToolStep,
  binding : ToolBinding,
) -> Json {
  {
    "contract": "moonsuite.pack-tool-step.v1",
    "pack_id": projection.pack_id,
    "product_id": projection.product_id,
    "pack_version": projection.version,
    "workflow_id": declaration.id,
    "workflow_version": declaration.version,
    "tool": binding,
    "config": step.config,
  }
}

///|
fn compiled_job_config(
  projection : @host.HostActivationProjection,
  declaration : PackWorkflowDeclaration,
  schedule : @pack.ScheduleDeclaration?,
) -> Json {
  let schedule_json : Json = match schedule {
    Some(schedule) => schedule.to_json()
    None => Json::null()
  }
  {
    "contract": "moonsuite.pack-job.v1",
    "pack_id": projection.pack_id,
    "product_id": projection.product_id,
    "pack_version": projection.version,
    "workflow_id": declaration.id,
    "workflow_version": declaration.version,
    "schedule": schedule_json,
  }
}

///|
/// Compile a validated installed pack workflow into native MoonClaw records.
///
/// Pack cron declarations are retained in `definition.config`. MoonClaw's
/// current scheduler is interval-based, so a selected cron schedule is marked
/// as `cron` without pretending it has an interval.
pub fn compile_workflow_job(
  projection : @host.HostActivationProjection,
  declaration : PackWorkflowDeclaration,
  now_ms : Int,
  schedule_id? : String,
) -> PackJobCompilation raise {
  require_pack_projection(projection)
  require_workflow_declaration(declaration)
  if declaration.pack_id != projection.pack_id ||
    declaration.product_id != projection.product_id {
    fail("pack workflow ownership does not match activation projection")
  }
  let projected = bindings(projection)
  let schedule = workflow_schedule(projection, declaration.id, schedule_id)
  let workflow_id = compiled_workflow_id(projection, declaration)
  let steps = declaration.steps.map(step => {
    let binding = match resolve(projected, step.tool_id) {
      Some(binding) => binding
      None =>
        fail(
          "pack workflow step " +
          step.id +
          " references undeclared tool " +
          step.tool_id,
        )
    }
    @job.WorkflowStepDefinition::{
      id: step.id,
      kind: "moonsuite.pack.tool",
      config: compiled_step_config(projection, declaration, step, binding),
      retry_policy: step.retry_policy,
    }
  })
  let workflow = @job.WorkflowDefinition::{
    id: workflow_id,
    kind: "moonsuite.pack.workflow",
    steps,
    output_bindings: declaration.output_bindings,
  }
  let definition = @job.JobDefinition::{
    id: compiled_job_id(projection, declaration, schedule),
    kind: "moonsuite.pack.job",
    enabled: true,
    config: compiled_job_config(projection, declaration, schedule),
    schedule: schedule.map(schedule => {
      kind: "cron",
      interval_minutes: None,
      timezone: Some(schedule.timezone),
    }),
    retry_policy: None,
    workflow_id: Some(workflow_id),
    created_at: now_ms,
    updated_at: now_ms,
    tags: [
      "job",
      "moonpack",
      "pack:\{projection.pack_id}",
      "product:\{projection.product_id}",
      "workflow:\{declaration.id}",
    ],
  }
  { definition, workflow }
}

///|
/// Persist a compiled pack workflow and create one pending durable run.
///
/// The function rejects existing run ids before changing pack job records and
/// preserves the original job creation time across pack upgrades.
pub async fn intake_workflow_run(
  runtime : @job.RuntimeManager,
  projection : @host.HostActivationProjection,
  declaration : PackWorkflowDeclaration,
  run_id : String,
  now_ms : Int,
  trigger? : @job.TriggerSource = Manual,
  schedule_id? : String,
) -> Result[PackJobIntake, String] {
  if !@pack.safe_identifier(run_id) {
    return Err("pack workflow run id is unsafe or incomplete")
  }
  if runtime.store().get_run(run_id) is Some(_) {
    return Err("pack workflow run id already exists: " + run_id)
  }
  let compilation = try {
    match schedule_id {
      Some(schedule_id) =>
        compile_workflow_job(projection, declaration, now_ms, schedule_id~)
      None => compile_workflow_job(projection, declaration, now_ms)
    }
  } catch {
    error => return Err("\{error}")
  }
  if runtime.is_job_active(compilation.definition.id) {
    return Err(
      "Pack workflow job already has an active run: " +
      compilation.definition.id,
    )
  }
  let definition = match
    runtime.store().get_definition(compilation.definition.id) {
    Some(existing) =>
      @job.JobDefinition::{
        ..compilation.definition,
        created_at: existing.created_at,
      }
    None => compilation.definition
  }
  runtime.register_workflow(compilation.workflow)
  runtime.register_definition(definition)
  match runtime.create_run(run_id, definition.id, trigger, now_ms) {
    Ok(run) => Ok({ definition, workflow: compilation.workflow, run })
    Err(error) => Err(error)
  }
}
