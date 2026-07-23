///|
/// Verified installed workflow loaded from the active MoonPack version.
pub(all) struct InstalledPackWorkflow {
  pointer : @installer.ActivePackPointer
  receipt : @installer.InstallationReceipt
  manifest : @pack.MoonPackManifest
  workflow_contract : @pack.ContractRef
  projection : @host.HostActivationProjection
  declaration : PackWorkflowDeclaration
} derive(Debug, ToJson, FromJson)

///|
/// Durable intake result for an installed workflow.
pub(all) struct InstalledPackWorkflowIntake {
  installed : InstalledPackWorkflow
  intake : PackJobIntake
} derive(Debug, ToJson, FromJson)

///|
/// Completed host execution for an installed workflow.
pub(all) struct InstalledPackWorkflowRun {
  installed : InstalledPackWorkflow
  intake : PackJobIntake
  execution : @job.WorkflowExecutionResult
}

///|
fn require_active_pack(
  pointer : @installer.ActivePackPointer,
  manifest : @pack.MoonPackManifest,
  pack_id : String,
) -> Unit raise {
  if pointer.contract != "moonsuite.active-pack.v1" {
    fail("unsupported active pack pointer")
  }
  if pointer.pack_id != pack_id ||
    manifest.id != pack_id ||
    manifest.version != pointer.version {
    fail("active pack pointer and installed manifest identity do not match")
  }
}

///|
async fn installed_pack_receipt(
  pointer : @installer.ActivePackPointer,
) -> @installer.InstallationReceipt {
  let receipt : @installer.InstallationReceipt = @json.from_json(
    @json.parse(
      @fsx.read_file(@pathx.join(pointer.installed_root, "receipt.json")),
    ),
  )
  if receipt.contract != "moonsuite.pack-installation.v1" ||
    receipt.pack_id != pointer.pack_id ||
    receipt.version != pointer.version ||
    receipt.installed_root != pointer.installed_root ||
    receipt.manifest_sha256 != pointer.manifest_sha256 {
    fail("active pack pointer and installation receipt do not match")
  }
  receipt
}

///|
fn installed_workflow_contract(
  manifest : @pack.MoonPackManifest,
  workflow_id : String,
) -> @pack.ContractRef raise {
  let matches = manifest.workflows.filter(contract => contract.id == workflow_id)
  guard matches is [contract] else {
    fail("unknown or duplicate installed pack workflow: " + workflow_id)
  }
  if !@pack.safe_artifact_path(contract.path) {
    fail("installed pack workflow path is unsafe: " + contract.path)
  }
  contract
}

///|
/// Load and verify a machine-readable workflow from the active installed pack.
pub async fn load_installed_workflow(
  workspace~ : String,
  pack_id~ : String,
  workflow_id~ : String,
) -> InstalledPackWorkflow {
  guard @installer.active_pack(workspace, pack_id) is Some(pointer) else {
    fail("pack is not active: " + pack_id)
  }
  let verification = @installer.verify_installed(
    workspace,
    pointer.pack_id,
    pointer.version,
  )
  if !verification.ok {
    fail("active pack verification failed: " + verification.issues.join("; "))
  }
  guard @installer.active_manifest(workspace, pack_id) is Some(manifest) else {
    fail("active pack manifest is unavailable: " + pack_id)
  }
  require_active_pack(pointer, manifest, pack_id)
  let receipt = installed_pack_receipt(pointer)
  let workflow_contract = installed_workflow_contract(manifest, workflow_id)
  let workflow_path = @pathx.join(
    pointer.installed_root,
    workflow_contract.path,
  )
  let declaration = decode_workflow_declaration(@fsx.read_file(workflow_path))
  if declaration.id != workflow_contract.id ||
    declaration.version != workflow_contract.version {
    fail("installed workflow declaration does not match its manifest contract")
  }
  {
    pointer,
    receipt,
    manifest,
    workflow_contract,
    projection: @host.activation_projection(manifest, pointer),
    declaration,
  }
}

///|
/// Load an active installed workflow and create its pending durable MoonClaw run.
pub async fn intake_installed_workflow(
  workspace~ : String,
  pack_id~ : String,
  workflow_id~ : String,
  run_id~ : String,
  now_ms~ : Int,
  trigger? : @job.TriggerSource = Manual,
  schedule_id? : String,
) -> InstalledPackWorkflowIntake {
  let installed = load_installed_workflow(workspace~, pack_id~, workflow_id~)
  let runtime = @job.RuntimeManager::new(
    root=@job.moonclaw_jobs_root(workspace),
  )
  runtime.load()
  let intake = match schedule_id {
    Some(schedule_id) =>
      intake_workflow_run(
        runtime,
        installed.projection,
        installed.declaration,
        run_id,
        now_ms,
        trigger~,
        schedule_id~,
      )
    None =>
      intake_workflow_run(
        runtime,
        installed.projection,
        installed.declaration,
        run_id,
        now_ms,
        trigger~,
      )
  }
  match intake {
    Ok(intake) => { installed, intake }
    Err(error) => fail(error)
  }
}

///|
/// Register the generic pack handler and advance an existing durable run.
pub async fn advance_pack_workflow_run(
  runtime : @job.RuntimeManager,
  run_id~ : String,
  executor~ : PackToolExecutor,
  policy~ : InvocationPolicy,
  now~ : () -> Int,
  initial_input? : Json,
) -> @job.WorkflowExecutionResult {
  let engine = @job.WorkflowEngine::new(runtime~)
  engine.register_handler(pack_tool_step_handler(executor, policy))
  let execution = match initial_input {
    Some(initial_input) =>
      engine.execute_run(run_id, now, initial_input=Some(initial_input))
    None => engine.execute_run(run_id, now)
  }
  match execution {
    Ok(execution) => execution
    Err(error) => fail(error)
  }
}

///|
/// Intake and execute one active installed pack workflow.
pub async fn run_installed_workflow(
  workspace~ : String,
  pack_id~ : String,
  workflow_id~ : String,
  run_id~ : String,
  executor~ : PackToolExecutor,
  policy~ : InvocationPolicy,
  now~ : () -> Int,
  initial_input? : Json,
  schedule_id? : String,
) -> InstalledPackWorkflowRun {
  let intake_result = match schedule_id {
    Some(schedule_id) =>
      intake_installed_workflow(
        workspace~,
        pack_id~,
        workflow_id~,
        run_id~,
        now_ms=now(),
        schedule_id~,
      )
    None =>
      intake_installed_workflow(
        workspace~,
        pack_id~,
        workflow_id~,
        run_id~,
        now_ms=now(),
      )
  }
  let runtime = @job.RuntimeManager::new(
    root=@job.moonclaw_jobs_root(workspace),
  )
  runtime.load()
  let execution = match initial_input {
    Some(initial_input) =>
      advance_pack_workflow_run(
        runtime,
        run_id~,
        executor~,
        policy~,
        now~,
        initial_input~,
      )
    None =>
      advance_pack_workflow_run(runtime, run_id~, executor~, policy~, now~)
  }
  {
    installed: intake_result.installed,
    intake: intake_result.intake,
    execution,
  }
}

///|
/// Intake and execute one active installed pack workflow through its declared
/// stdin/stdout command steps.
pub async fn run_installed_command_workflow(
  workspace~ : String,
  pack_id~ : String,
  workflow_id~ : String,
  run_id~ : String,
  policy~ : InvocationPolicy,
  now~ : () -> Int,
  initial_input? : Json,
  schedule_id? : String,
) -> InstalledPackWorkflowRun {
  let intake_result = match schedule_id {
    Some(schedule_id) =>
      intake_installed_workflow(
        workspace~,
        pack_id~,
        workflow_id~,
        run_id~,
        now_ms=now(),
        schedule_id~,
      )
    None =>
      intake_installed_workflow(
        workspace~,
        pack_id~,
        workflow_id~,
        run_id~,
        now_ms=now(),
      )
  }
  let runtime = @job.RuntimeManager::new(
    root=@job.moonclaw_jobs_root(workspace),
  )
  runtime.load()
  let executor = installed_pack_command_executor(
    intake_result.installed,
    max_timeout_ms=policy.timeout_ms,
  )
  let execution = match initial_input {
    Some(initial_input) =>
      advance_pack_workflow_run(
        runtime,
        run_id~,
        executor~,
        policy~,
        now~,
        initial_input~,
      )
    None =>
      advance_pack_workflow_run(runtime, run_id~, executor~, policy~, now~)
  }
  {
    installed: intake_result.installed,
    intake: intake_result.intake,
    execution,
  }
}
