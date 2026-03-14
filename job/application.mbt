///|
pub struct GatewayJobApp {
  state : GatewayJobState
  cwd : String
  home : String
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
  next_id~ : () -> String,
  now~ : () -> Int,
) -> GatewayJobApp {
  GatewayJobApp::{ state: GatewayJobState::new(root~), cwd, home, next_id, now }
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
pub fn GatewayJobApp::now(self : GatewayJobApp) -> Int {
  (self.now)()
}

///|
pub fn GatewayJobApp::next_id(self : GatewayJobApp) -> String {
  (self.next_id)()
}

///|
fn unique_memory_hits(
  hits : Array[MemorySearchHit],
  extra : Array[MemorySearchHit],
  limit : Int,
) -> Array[MemorySearchHit] {
  let combined : Array[MemorySearchHit] = []
  let seen : Map[String, Bool] = {}
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
fn GatewayJobApp::planning_memory_context(
  self : GatewayJobApp,
  request_text : String,
  channel_id : String?,
  account_id : String?,
  recipient : String?,
  thread_id : String?,
) -> String {
  let memories = MemoryService::new(store=self.runtime().store())
  let scoped_hits = memories.search(
    request_text,
    query=MemoryQuery::new(
      workspace=Some(self.cwd),
      channel_id~,
      account_id~,
      recipient~,
      thread_id~,
      status=Some(MemoryStatus::Active),
    ),
    max_hits=4,
  )
  let workspace_hits = memories.search(
    request_text,
    query=MemoryQuery::new(
      workspace=Some(self.cwd),
      status=Some(MemoryStatus::Active),
    ),
    max_hits=4,
  )
  render_memory_hits_prompt(unique_memory_hits(scoped_hits, workspace_hits, 4))
}

///|
pub async fn GatewayJobApp::plan_proposal(
  self : GatewayJobApp,
  request_text : String,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
) -> JobProposal {
  let memory_context = self.planning_memory_context(
    request_text, channel_id, account_id, recipient, thread_id,
  )
  plan_job_proposal(
    self.next_id(),
    request_text,
    self.now(),
    channel_id~,
    account_id~,
    recipient~,
    thread_id~,
    model~,
    cwd=self.cwd,
    home=Some(self.home),
    memory_context=Some(memory_context),
  )
}

///|
pub async fn GatewayJobApp::revise_proposal(
  self : GatewayJobApp,
  proposal : JobProposal,
  guidance : String,
) -> JobProposal {
  let memory_context = self.planning_memory_context(
    proposal.request_text,
    proposal.channel_id,
    proposal.account_id,
    proposal.recipient,
    proposal.thread_id,
  )
  revise_job_proposal(
    proposal,
    guidance,
    self.now(),
    cwd=self.cwd,
    home=Some(self.home),
    memory_context=Some(memory_context),
  )
}

///|
pub fn GatewayJobApp::compile_proposal(
  self : GatewayJobApp,
  proposal : JobProposal,
) -> ProposalCompilation {
  compile_job_proposal(proposal, self.now(), self.cwd, self.home)
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
  launch_run : async (String) -> Result[JobRun, String],
) -> Result[ConfirmProposalResult, String] {
  match ensure_draft_proposal(proposal, proposal_id) {
    Some(error) => return Err(error)
    None => ()
  }
  let compilation = self.compile_proposal(proposal)
  let definition = compilation.definition
  let workflow = compilation.workflow
  self.runtime().register_definition(definition)
  self.runtime().register_workflow(workflow)
  for binding in compilation.bindings {
    self.runtime().store().save_chat_binding(binding)
  }
  let run = match launch_run(definition.id) {
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
  Ok(ConfirmProposalResult::{ compilation, run })
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
  ProposalPlanner::new(run=async fn(request_text, _cwd, _home) {
    self.plan_proposal(request_text)
  })
}

///|
fn GatewayJobApp::proposal_compiler(self : GatewayJobApp) -> ProposalCompiler {
  ProposalCompiler::new(run=fn(proposal, _now_ms, _cwd, _home) {
    self.compile_proposal(proposal)
  })
}

///|
pub fn GatewayJobApp::new_workflow_engine(
  self : GatewayJobApp,
) -> WorkflowEngine {
  let runtime = self.runtime()
  let engine = WorkflowEngine::new(runtime~)
  engine.register_handler(analysis_step_handler(runtime~))
  engine.register_handler(
    subjob_step_handler(
      runtime~,
      planner=self.proposal_planner(),
      compiler=self.proposal_compiler(),
      engine_factory=fn() { self.new_workflow_engine() },
      now=fn() { self.now() },
      next_run_id=fn() { self.next_id() },
    ),
  )
  engine.register_handler(research_topic_sync_step_handler(runtime~))
  engine.register_handler(research_paper_fetch_step_handler(runtime~))
  engine.register_handler(research_paper_parse_step_handler(runtime~))
  engine.register_handler(research_paper_analyze_step_handler(runtime~))
  engine
}
