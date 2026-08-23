///|
pub struct GatewayJobApp {
  state : GatewayJobState
  cwd : String
  home : String
  workspace : @workspace.WorkspaceRuntime
  next_id : () -> String
  now : () -> Int
}

///|
pub struct ConfirmProposalResult {
  compilation : ProposalCompilation
  run : JobRun
}

///|
pub fn GatewayJobApp::new(
  root~ : String,
  cwd~ : String,
  home~ : String,
  workspace~ : @workspace.WorkspaceRuntime,
  next_id~ : () -> String,
  now~ : () -> Int,
) -> GatewayJobApp {
  { state: GatewayJobState::new(root~), cwd, home, workspace, next_id, now }
}

///|
pub async fn GatewayJobApp::load(self : GatewayJobApp) -> Unit {
  self.state.load()
}

///|
pub fn GatewayJobApp::runtime(self : GatewayJobApp) -> RuntimeManager {
  self.state.runtime()
}

///|
pub fn GatewayJobApp::state(self : GatewayJobApp) -> GatewayJobState {
  self.state
}

///|
pub fn GatewayJobApp::workspace_root(self : GatewayJobApp) -> String {
  self.workspace.root()
}

///|
pub fn GatewayJobApp::workspace_prompt_context(self : GatewayJobApp) -> String {
  self.workspace.prompt_context()
}

///|
pub fn GatewayJobApp::now(self : GatewayJobApp) -> Int {
  (self.now)()
}

///|
pub fn GatewayJobApp::next_id(self : GatewayJobApp) -> String {
  (self.next_id)()
}

///|
pub fn GatewayJobApp::next_run_id(self : GatewayJobApp) -> String {
  let now_ms = self.now()
  let seed = self.next_id()
  let base = human_readable_run_id(now_ms, seed)
  let store = self.runtime().store()
  let mut i = 0
  while i < 1000 {
    let candidate = if i == 0 { base } else { "\{base}-\{i}" }
    if store.get_run(candidate) is None {
      return candidate
    }
    i += 1
  }
  "\{base}-\{now_ms}-\{store.list_runs().length()}"
}

///|
fn unique_memory_hits(
  hits : Array[MemorySearchHit],
  extra : Array[MemorySearchHit],
  limit : Int,
) -> Array[MemorySearchHit] {
  let combined : Array[MemorySearchHit] = []
  let seen : Map[String, Bool] = Map([])
  for hit in hits {
    if combined.length() >= limit {
      break
    }
    if !seen.contains(hit.memory_id) {
      seen.set(hit.memory_id, true)
      combined.push(hit)
    }
  }
  for hit in extra {
    if combined.length() >= limit {
      break
    }
    if !seen.contains(hit.memory_id) {
      seen.set(hit.memory_id, true)
      combined.push(hit)
    }
  }
  combined
}

///|
async fn GatewayJobApp::planning_memory_context(
  self : GatewayJobApp,
  request_text : String,
  workspace_root : String,
  channel_id : String?,
  account_id : String?,
  recipient : String?,
  thread_id : String?,
) -> String {
  let memories = MemoryService::new(store=self.runtime().store())
  let scoped_hits = memories.search(
    request_text,
    query=MemoryQuery::new(
      workspace=Some(workspace_root),
      channel_id~,
      account_id~,
      recipient~,
      thread_id~,
      status=Some(Active),
    ),
    max_hits=4,
  )
  let workspace_hits = memories.search(
    request_text,
    query=MemoryQuery::new(workspace=Some(workspace_root), status=Some(Active)),
    max_hits=4,
  )
  let workspace_snapshot = @workspace.load_workspace_snapshot_from_root(
    workspace_root,
    configured_from="job",
  )
  let sections : Array[String] = []
  let memory_prompt = render_memory_hits_prompt(
    unique_memory_hits(scoped_hits, workspace_hits, 4),
  )
  if !workspace_snapshot.prompt_context.is_blank() {
    sections.push(workspace_snapshot.prompt_context)
  }
  if !memory_prompt.is_blank() {
    sections.push(memory_prompt)
  }
  sections.join("\n\n")
}

///|
pub async fn GatewayJobApp::plan_proposal_in_workspace(
  self : GatewayJobApp,
  request_text : String,
  workspace_root : String,
  cwd : String,
  e2e_mode? : Bool = false,
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
) -> JobProposal {
  let now_ms = self.now()
  let memory_context = self.planning_memory_context(
    request_text, workspace_root, channel_id, account_id, recipient, thread_id,
  )
  let proposal_id = human_readable_proposal_id(
    request_text,
    now_ms,
    self.next_id(),
  )
  if e2e_mode {
    plan_e2e_job_proposal(
      proposal_id,
      request_text,
      now_ms,
      intake~,
      channel_id~,
      account_id~,
      recipient~,
      thread_id~,
      model~,
      cwd~,
      home=Some(self.home),
      workspace=Some(workspace_root),
      memory_context=Some(memory_context),
    )
  } else {
    plan_job_proposal(
      proposal_id,
      request_text,
      now_ms,
      intake~,
      channel_id~,
      account_id~,
      recipient~,
      thread_id~,
      model~,
      cwd~,
      home=Some(self.home),
      workspace=Some(workspace_root),
      memory_context=Some(memory_context),
    )
  }
}

///|
pub async fn GatewayJobApp::plan_mode_in_workspace(
  self : GatewayJobApp,
  request_text : String,
  workspace_root : String,
  cwd : String,
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
  executor? : AnalysisExecutor = default_analysis_executor(),
) -> JobPlanPreview {
  let memory_context = self.planning_memory_context(
    request_text, workspace_root, channel_id, account_id, recipient, thread_id,
  )
  plan_chat_mode(
    request_text,
    self.now(),
    executor~,
    intake~,
    channel_id~,
    account_id~,
    recipient~,
    thread_id~,
    model~,
    cwd~,
    home=Some(self.home),
    workspace=Some(workspace_root),
    memory_context=Some(memory_context),
  )
}

///|
pub async fn GatewayJobApp::plan_mode(
  self : GatewayJobApp,
  request_text : String,
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
  executor? : AnalysisExecutor = default_analysis_executor(),
) -> JobPlanPreview {
  self.plan_mode_in_workspace(
    request_text,
    self.workspace_root(),
    self.cwd,
    intake~,
    channel_id~,
    account_id~,
    recipient~,
    thread_id~,
    model~,
    executor~,
  )
}

///|
pub async fn GatewayJobApp::plan_proposal(
  self : GatewayJobApp,
  request_text : String,
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
) -> JobProposal {
  self.plan_proposal_in_workspace(
    request_text,
    self.workspace_root(),
    self.cwd,
    intake~,
    channel_id~,
    account_id~,
    recipient~,
    thread_id~,
    model~,
  )
}

///|
pub async fn GatewayJobApp::plan_e2e_proposal_in_workspace(
  self : GatewayJobApp,
  request_text : String,
  workspace_root : String,
  cwd : String,
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
) -> JobProposal {
  self.plan_proposal_in_workspace(
    request_text,
    workspace_root,
    cwd,
    e2e_mode=true,
    intake~,
    channel_id~,
    account_id~,
    recipient~,
    thread_id~,
    model~,
  )
}

///|
pub async fn GatewayJobApp::plan_e2e_proposal(
  self : GatewayJobApp,
  request_text : String,
  intake? : Json? = None,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
) -> JobProposal {
  self.plan_e2e_proposal_in_workspace(
    request_text,
    self.workspace_root(),
    self.cwd,
    intake~,
    channel_id~,
    account_id~,
    recipient~,
    thread_id~,
    model~,
  )
}

///|
pub async fn GatewayJobApp::revise_proposal_in_workspace(
  self : GatewayJobApp,
  proposal : JobProposal,
  guidance : String,
  workspace_root : String,
  cwd : String,
) -> JobProposal {
  let memory_context = self.planning_memory_context(
    proposal.request_text,
    workspace_root,
    proposal.channel_id,
    proposal.account_id,
    proposal.recipient,
    proposal.thread_id,
  )
  revise_job_proposal(
    proposal,
    guidance,
    self.now(),
    cwd~,
    home=Some(self.home),
    workspace=Some(workspace_root),
    memory_context=Some(memory_context),
  )
}

///|
pub async fn GatewayJobApp::revise_proposal(
  self : GatewayJobApp,
  proposal : JobProposal,
  guidance : String,
) -> JobProposal {
  self.revise_proposal_in_workspace(
    proposal,
    guidance,
    self.workspace_root(),
    self.cwd,
  )
}

///|
pub fn GatewayJobApp::compile_proposal_in_workspace(
  self : GatewayJobApp,
  proposal : JobProposal,
  cwd : String,
  workspace_root : String,
) -> ProposalCompilation {
  compile_job_proposal(proposal, self.now(), cwd, self.home, workspace_root~)
}

///|
pub fn GatewayJobApp::compile_proposal(
  self : GatewayJobApp,
  proposal : JobProposal,
) -> ProposalCompilation {
  self.compile_proposal_in_workspace(proposal, self.cwd, self.workspace_root())
}

///|
pub async fn GatewayJobApp::revise_draft_proposal(
  self : GatewayJobApp,
  proposal : JobProposal,
  proposal_id : String,
  guidance : String,
) -> Result[JobProposal, String] {
  match ensure_draft_proposal(proposal, proposal_id) {
    Some(error) => Err(error)
    None => Ok(self.revise_proposal(proposal, guidance))
  }
}

///|
pub async fn GatewayJobApp::confirm_proposal(
  self : GatewayJobApp,
  proposal : JobProposal,
  proposal_id : String,
  launch_run : async (String, Json?) -> Result[JobRun, String],
) -> Result[ConfirmProposalResult, String] {
  self.confirm_proposal_in_workspace(
    proposal,
    proposal_id,
    self.cwd,
    self.workspace_root(),
    launch_run,
  )
}

///|
pub async fn GatewayJobApp::confirm_proposal_in_workspace(
  self : GatewayJobApp,
  proposal : JobProposal,
  proposal_id : String,
  cwd : String,
  workspace_root : String,
  launch_run : async (String, Json?) -> Result[JobRun, String],
) -> Result[ConfirmProposalResult, String] {
  match ensure_draft_proposal(proposal, proposal_id) {
    Some(error) => return Err(error)
    None => ()
  }
  let compilation = self.compile_proposal_in_workspace(
    proposal, cwd, workspace_root,
  )
  let definition = compilation.definition
  let workflow = compilation.workflow
  self.runtime().register_definition(definition)
  self.runtime().register_workflow(workflow)
  for binding in compilation.bindings {
    self.runtime().store().save_chat_binding(binding)
  }
  let run = match launch_run(definition.id, proposal_initial_input(proposal)) {
    Ok(run) => run
    Err(error) => return Err(error)
  }
  save_confirmed_job_proposal(
    self.runtime().store(),
    proposal,
    compilation,
    run.id,
    self.now(),
  )
  Ok({ compilation, run })
}

///|
pub async fn GatewayJobApp::reject_proposal(
  self : GatewayJobApp,
  proposal : JobProposal,
) -> Unit {
  save_rejected_job_proposal(self.runtime().store(), proposal, self.now())
}

///|
fn GatewayJobApp::proposal_planner(self : GatewayJobApp) -> ProposalPlanner {
  ProposalPlanner::new(run=async fn(request_text, cwd, _home) {
    self.plan_proposal_in_workspace(request_text, cwd, cwd)
  })
}

///|
fn GatewayJobApp::proposal_compiler(self : GatewayJobApp) -> ProposalCompiler {
  ProposalCompiler::new(run=fn(proposal, _now_ms, cwd, _home) {
    self.compile_proposal_in_workspace(proposal, cwd, cwd)
  })
}

///|
pub fn GatewayJobApp::new_workflow_engine(
  self : GatewayJobApp,
) -> WorkflowEngine {
  self.new_workflow_engine_with_executors()
}

///|
pub fn GatewayJobApp::new_workflow_engine_with_child_executor(
  self : GatewayJobApp,
  child_executor? : ChildRunExecutor? = None,
) -> WorkflowEngine {
  self.new_workflow_engine_with_executors(child_executor~)
}

///|
pub fn GatewayJobApp::new_workflow_engine_with_executors(
  self : GatewayJobApp,
  child_executor? : ChildRunExecutor? = None,
  analysis_executor? : AnalysisExecutor? = None,
) -> WorkflowEngine {
  let runtime = self.runtime()
  let engine = WorkflowEngine::new(runtime~)
  engine.register_handler(
    analysis_step_handler(
      runtime~,
      executor=analysis_executor.unwrap_or(default_analysis_executor()),
      compiler=Some(self.proposal_compiler()),
      engine_factory=Some(fn() {
        self.new_workflow_engine_with_executors(
          child_executor~,
          analysis_executor~,
        )
      }),
      child_executor~,
      next_run_id=fn() { self.next_run_id() },
    ),
  )
  engine.register_handler(
    subjob_step_handler(
      runtime~,
      planner=self.proposal_planner(),
      compiler=self.proposal_compiler(),
      engine_factory=fn() {
        self.new_workflow_engine_with_executors(
          child_executor~,
          analysis_executor~,
        )
      },
      child_executor~,
      now=fn() { self.now() },
      next_run_id=fn() { self.next_run_id() },
    ),
  )
  engine
}
