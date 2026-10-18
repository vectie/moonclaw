///|
/// Opt-in one-off imports have stable proposal/run identities. Ordinary external
/// imports retain their historical behavior. The exact packet, profile and
/// workspace binding is durable before the runtime is allowed to start.
pub(all) struct ExternalOneoffReceipt {
  packet_id : String
  proposal_id : String
  run_id : String
  status : String
  workspace_dir : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
fn oneoff_safe_id(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 96 &&
  value != "." &&
  value != ".." &&
  value
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '-' ||
    c == '_'
  })
}

///|
pub async fn GatewayJobApp::start_external_oneoff_file(
  self : GatewayJobApp,
  packet_path : String,
  execute~ : Bool = true,
  analysis_executor~ : AnalysisExecutor? = None,
) -> Result[ExternalOneoffReceipt, String] {
  let text = @fsx.read_file(packet_path)
  guard text.length() <= 2097152 else {
    return Err("One-off packet exceeds 2 MiB")
  }
  let packet = match parse_external_proposal_packet_text(text) {
    Ok(packet) => packet
    Err(error) => return Err(error)
  }
  guard packet.packet_id is Some(key) && oneoff_safe_id(key) else {
    return Err("One-off packet requires a safe stable packet_id")
  }
  let profile = match load_job_profile(self.home, self.cwd, packet.profile) {
    Some(profile) => profile
    None =>
      return Err(
        "Configure the one-off profile in moonclaw.jobs.json before starting",
      )
  }
  let root = self.runtime().store().root_dir() + "/oneoff/" + key
  @fsx.make_directory(root, recursive=true, exists_ok=true)
  let lock = @fs.open(
    root + "/request.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  defer lock.close()
  lock.lock(Exclusive)
  defer lock.unlock()
  let proposal_id = "oneoff-" + key
  let run_id = "run-oneoff-" + key
  // The pinned legacy SystemStore lock is nonblocking across processes. Keep
  // this opt-in one-off lifecycle serialized per runtime home, including its
  // workspace/checkpoint writes. Town launches in the background, so status
  // reads remain responsive while participants execute sequentially.
  let initialize = @fs.open(
    self.runtime().store().root_dir() + "/oneoff/initialize.lock",
    mode=ReadWrite,
    create_mode=OpenOrCreate,
  )
  defer initialize.close()
  initialize.lock(Exclusive)
  defer initialize.unlock()
  // Reload after acquiring the cross-process lock: a duplicate caller may have
  // waited while the first caller finished its actual runtime execution.
  self.load()
  let binding : Json = {
    "contract_version": "moonclaw.external-oneoff-binding.v1",
    "packet_text": text,
    "packet_path": packet_path,
    "cwd": self.cwd,
    "home": self.home,
    "workspace": self.workspace_root(),
    "profile": profile.to_json(),
  }
  let binding_path = root + "/binding.json"
  if @fsx.exists(binding_path) {
    guard @fsx.read_file(binding_path) == binding.stringify() else {
      return Err(
        "One-off request identity already binds different packet, profile or workspace bytes",
      )
    }
  } else {
    let temporary = root + "/binding.next"
    if @fsx.exists(temporary) {
      @fs.remove(temporary)
    }
    @fs.write_file(
      temporary,
      binding.stringify(),
      create_mode=CreateNew,
      sync=Full,
    )
    @fs.rename(temporary, binding_path, replace=false)
  }
  let store = self.runtime().store()
  let proposal = match store.get_job_proposal(proposal_id) {
    Some(proposal) => proposal
    None => {
      let imported = proposal_with_external_packet(
        proposal_id,
        packet,
        packet_path,
        self.now(),
      )
      let profiled = apply_oneoff_profile(
        imported,
        profile,
        self.workspace_root(),
      )
      let profiled = JobProposal::{
        ..profiled,
        profile_metadata: match packet.output_contract {
          Some(String(contract)) =>
            merge_json_metadata(profiled.profile_metadata, {
              "output_contract": contract,
            })
          _ => profiled.profile_metadata
        },
        steps: profiled.steps.map(step => {
          ..step,
          metadata: external_packet_step_metadata(
            step.metadata,
            packet,
            packet_path,
          ),
        }),
      }
      store.save_job_proposal(profiled)
      profiled
    }
  }
  let compilation = self.compile_proposal(proposal)
  if store.get_definition(compilation.definition.id) is None {
    self.runtime().register_definition(compilation.definition)
  }
  if store.get_workflow(compilation.workflow.id) is None {
    self.runtime().register_workflow(compilation.workflow)
  }
  if store.get_run(run_id) is None {
    for binding in compilation.bindings {
      store.save_chat_binding(binding)
    }
  }
  let run = match store.get_run(run_id) {
    Some(run) => {
      guard run.job_id == compilation.definition.id else {
        return Err("One-off run identity belongs to another definition")
      }
      run
    }
    None =>
      match
        self
        .runtime()
        .trigger_definition(
          run_id,
          compilation.definition.id,
          Manual,
          self.now(),
        ) {
        Ok(run) => run
        Err(error) => return Err(error)
      }
  }
  if !(proposal.status is Confirmed) {
    save_confirmed_job_proposal(
      store,
      proposal,
      compilation,
      run_id,
      self.now(),
    )
  }
  // Only an unstarted durable run may execute. Running/unknown work is never
  // replayed, and a failed/cancelled result requires a fresh source revision.
  let result = if execute && run.status is Pending {
    match
      self.execute_existing_run(
        run_id,
        initial_input=proposal_initial_input(proposal),
        analysis_executor~,
      ) {
      Ok(run) => run
      Err(error) => return Err(error)
    }
  } else {
    run
  }
  Ok({
    packet_id: key,
    proposal_id,
    run_id,
    status: match result.status {
      Pending => "Pending"
      Running => "Running"
      WaitingForInput => "WaitingForInput"
      Succeeded => "Succeeded"
      Failed => "Failed"
      Cancelled => "Cancelled"
    },
    workspace_dir: result.workspace_dir,
  })
}

///|
pub extend ExternalOneoffReceipt with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ExternalOneoffReceipt with Eq::{not_equal, equal}

///|
pub extend ExternalOneoffReceipt with ToJson::{to_json}

///|
pub extend ExternalOneoffReceipt with @moonbitlang/core/json.FromJson::{
  from_json,
}
