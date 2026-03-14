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
pub async fn GatewayJobApp::plan_proposal(
  self : GatewayJobApp,
  request_text : String,
  channel_id? : String? = None,
  account_id? : String? = None,
  recipient? : String? = None,
  thread_id? : String? = None,
  model? : String? = None,
) -> JobProposal {
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
  )
}

///|
pub async fn GatewayJobApp::revise_proposal(
  self : GatewayJobApp,
  proposal : JobProposal,
  guidance : String,
) -> JobProposal {
  revise_job_proposal(
    proposal,
    guidance,
    self.now(),
    cwd=self.cwd,
    home=Some(self.home),
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
