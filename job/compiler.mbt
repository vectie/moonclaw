///|
pub(all) struct ProposalCompilation {
  family : String
  template : String
  required_capabilities : Array[String]
  missing_capabilities : Array[String]
  compiler_notes : Array[String]
  definition : JobDefinition
  workflow : WorkflowDefinition
  bindings : Array[ChatBinding]
}

///|
fn normalized_request_text(text : String) -> String {
  text.trim().to_string().to_lower()
}

///|
fn proposal_mentions_research(proposal : JobProposal) -> Bool {
  if proposal.tags.contains("research") {
    return true
  }
  let lower = normalized_request_text(proposal.request_text)
  lower.contains("arxiv") ||
  lower.contains("paper") ||
  lower.contains("research") ||
  lower.contains("literature") ||
  lower.contains("vla") ||
  lower.contains("vision-language-action")
}

///|
fn proposal_mentions_monitoring(proposal : JobProposal) -> Bool {
  let lower = normalized_request_text(proposal.request_text)
  lower.contains("daily") ||
  lower.contains("weekly") ||
  lower.contains("regularly") ||
  lower.contains("track") ||
  lower.contains("watch") ||
  lower.contains("monitor") ||
  lower.contains("yesterday")
}

///|
fn proposal_mentions_tool_work(proposal : JobProposal) -> Bool {
  let lower = normalized_request_text(proposal.request_text)
  lower.contains("fetch") ||
  lower.contains("collect") ||
  lower.contains("search") ||
  lower.contains("crawl") ||
  lower.contains("tool") ||
  lower.contains("repo") ||
  lower.contains("repository") ||
  lower.contains("github")
}

///|
fn step_title_contains(proposal : JobProposal, text : String) -> Bool {
  let needle = text.to_lower()
  proposal.steps.any(fn(step) {
    step.title.to_lower().contains(needle) ||
    step.prompt.to_lower().contains(needle)
  })
}

///|
fn compiled_family_for_proposal(proposal : JobProposal) -> String {
  match proposal.suggested_family {
    Some(family) if !family.trim().to_string().is_blank() =>
      family.trim().to_string()
    _ =>
      if proposal_mentions_research(proposal) {
        "research"
      } else {
        "generic"
      }
  }
}

///|
fn compiled_template_for_proposal(
  proposal : JobProposal,
  family : String,
) -> String {
  match proposal.suggested_template {
    Some(template) if !template.trim().to_string().is_blank() => {
      let template = template.trim().to_string()
      if family == "generic" &&
        template == "generic.analysis" &&
        proposal_mentions_tool_work(proposal) {
        "generic.tool_workflow"
      } else {
        template
      }
    }
    _ =>
      match family {
        "research" =>
          if proposal_mentions_monitoring(proposal) ||
            step_title_contains(proposal, "search") ||
            step_title_contains(proposal, "filter") {
            "research.topic_watch"
          } else {
            "research.topic_review"
          }
        _ =>
          if proposal_mentions_tool_work(proposal) {
            "generic.tool_workflow"
          } else {
            "generic.analysis"
          }
      }
  }
}

///|
fn ordered_unique_strings(items : Array[String]) -> Array[String] {
  let result : Array[String] = []
  for item in items {
    if !item.is_blank() && !result.contains(item) {
      result.push(item)
    }
  }
  result
}

///|
fn inferred_capabilities_for_proposal(
  proposal : JobProposal,
  family : String,
) -> Array[String] {
  let capabilities : Array[String] = []
  if family == "research" {
    capabilities.push("research.arxiv_sync")
    if step_title_contains(proposal, "fetch") ||
      step_title_contains(proposal, "download") {
      capabilities.push("research.paper_fetch")
    }
    capabilities.push("analysis.summarize")
    capabilities.push("analysis.report")
  } else {
    capabilities.push("analysis.plan")
    capabilities.push("analysis.execute")
    capabilities.push("analysis.report")
  }
  capabilities
}

///|
fn candidate_templates_for_proposal(
  _proposal : JobProposal,
  family : String,
  base_template : String,
  capabilities : Array[String],
  should_delegate : Bool,
) -> Array[String] {
  let preferred = preferred_templates_for_capabilities(capabilities)
  let candidates = match family {
    "research" =>
      if should_delegate {
        [
          "research.delegated_review", base_template, ..preferred, "research.topic_watch",
          "research.topic_review", "generic.delegated", "generic.tool_workflow",
          "generic.analysis",
        ]
      } else {
        [
          base_template, ..preferred, "research.topic_watch", "research.topic_review",
          "generic.tool_workflow", "generic.analysis",
        ]
      }
    _ =>
      if should_delegate {
        [
          "generic.delegated", base_template, ..preferred, "generic.tool_workflow",
          "generic.analysis",
        ]
      } else {
        [
          base_template, ..preferred, "generic.tool_workflow", "generic.analysis",
        ]
      }
  }
  ordered_unique_strings(candidates)
}

///|
fn template_missing_count(template_id : String) -> Int {
  match template_definition(template_id) {
    Some(template) =>
      missing_capabilities(template.required_capabilities).length()
    None => 10_000
  }
}

///|
fn select_compilation_template(
  proposal : JobProposal,
  family : String,
  base_template : String,
  capabilities : Array[String],
  should_delegate : Bool,
) -> String {
  let candidates = candidate_templates_for_proposal(
    proposal, family, base_template, capabilities, should_delegate,
  )
  for candidate in candidates {
    match template_definition(candidate) {
      Some(template) if missing_capabilities(template.required_capabilities).is_empty() =>
        return template.id
      _ => ()
    }
  }
  let mut best = "generic.analysis"
  let mut best_missing = 10_000
  for candidate in candidates {
    let missing = template_missing_count(candidate)
    if missing < best_missing {
      best = candidate
      best_missing = missing
    }
  }
  best
}

///|
fn proposal_should_delegate(
  proposal : JobProposal,
  family : String,
  capabilities : Array[String],
) -> Bool {
  if !missing_capabilities(capabilities).is_empty() {
    return true
  }
  if proposal.steps.length() >= 6 {
    return true
  }
  let lower = normalized_request_text(proposal.request_text)
  if lower.contains("for each") ||
    lower.contains("each paper") ||
    lower.contains("compare") ||
    lower.contains("break down") ||
    lower.contains("subtask") {
    return true
  }
  family == "research" &&
  (
    step_title_contains(proposal, "compare") ||
    step_title_contains(proposal, "screen")
  )
}

///|
fn compiler_notes_for_selection(
  proposal : JobProposal,
  family : String,
  template : String,
  resolved_template : String,
  capabilities : Array[String],
  should_delegate : Bool,
) -> Array[String] {
  let notes = ["Family selected: \{family}"]
  let missing_names = missing_capabilities(capabilities).join(", ")
  let base_missing = template_definition(template)
    .map(fn(definition) {
      missing_capabilities(definition.required_capabilities).length()
    })
    .unwrap_or(10_000)
  let resolved_missing = template_definition(resolved_template)
    .map(fn(definition) {
      missing_capabilities(definition.required_capabilities).length()
    })
    .unwrap_or(10_000)
  if template != resolved_template {
    notes.push("Template routed from \{template} to \{resolved_template}")
    if resolved_missing < base_missing {
      notes.push(
        "Routing preferred the template with better capability coverage.",
      )
    }
  } else {
    notes.push("Template selected: \{resolved_template}")
  }
  let missing = missing_capabilities(capabilities)
  if !missing.is_empty() {
    notes.push("Missing capabilities: \{missing_names}")
  }
  if should_delegate {
    notes.push(
      "Delegation enabled because the request is broad or decomposable.",
    )
  }
  let lower = normalized_request_text(proposal.request_text)
  if lower.contains("for each") || lower.contains("each paper") {
    notes.push("Detected per-item execution in the request.")
  }
  if lower.contains("compare") {
    notes.push("Detected comparison work that benefits from child runs.")
  }
  notes
}

///|
pub fn explain_proposal_compilation_hints(
  proposal : JobProposal,
) -> (String, String, Array[String], Array[String], Array[String]) {
  let family = compiled_family_for_proposal(proposal)
  let template = compiled_template_for_proposal(proposal, family)
  let capabilities = inferred_capabilities_for_proposal(proposal, family)
  let should_delegate = proposal_should_delegate(proposal, family, capabilities)
  let resolved_template = select_compilation_template(
    proposal, family, template, capabilities, should_delegate,
  )
  (
    family,
    resolved_template,
    capabilities,
    missing_capabilities(capabilities),
    compiler_notes_for_selection(
      proposal, family, template, resolved_template, capabilities, should_delegate,
    ),
  )
}

///|
fn selected_template_skills(template : String) -> Array[String] {
  template_default_skills(template)
}

///|
fn normalized_topic_id(text : String) -> String {
  let lowered = text
    .to_lower()
    .replace(old="vision-language-action", new="vla")
    .replace(old=" ", new="-")
    .replace(old="_", new="-")
    .replace(old="/", new="-")
    .replace(old=":", new="-")
    .replace(old=",", new="-")
  let cleaned = lowered
    .split("-")
    .map(fn(part) { part.to_string().trim().to_string() })
    .collect()
    .filter(fn(part) { !part.is_blank() })
    .join("-")
  if cleaned.is_blank() {
    "research-topic"
  } else {
    cleaned
  }
}

///|
fn inferred_research_query(proposal : JobProposal) -> String {
  let lower = normalized_request_text(proposal.request_text)
  if lower.contains("vision-language-action") {
    "all:\"vision-language-action\" OR all:VLA"
  } else if lower.contains("vla") {
    "all:\"vision-language-action\" OR all:VLA"
  } else if lower.contains("multimodal") && lower.contains("agent") {
    "all:multimodal AND all:agent"
  } else if lower.contains("agent") {
    "all:agent"
  } else if lower.contains("paper") || lower.contains("research") {
    "all:\{proposal.request_text}"
  } else {
    "all:\{proposal.title}"
  }
}

///|
fn inferred_research_topic_id(proposal : JobProposal) -> String {
  let lower = normalized_request_text(proposal.request_text)
  if lower.contains("vision-language-action") || lower.contains("vla") {
    "vla"
  } else if lower.contains("agent") {
    "agent-systems"
  } else {
    normalized_topic_id(proposal.title)
  }
}

///|
fn default_research_summary_prompt(
  proposal : JobProposal,
  topic_id : String,
) -> String {
  [
    "Use the synced research artifacts for topic `\{topic_id}` to summarize the most important papers.",
    "Focus on novelty, methods, evidence quality, and practical relevance.",
    "Original job request: \{proposal.request_text}",
  ].join("\n\n")
}

///|
fn default_research_report_prompt(_proposal : JobProposal) -> String {
  [
    "Prepare the final research report for this job.", "Use earlier step outputs and keep the result concise but decision-useful.",
    "Include what matters, why it matters, and the recommended next actions.",
  ].join("\n\n")
}

///|
fn compile_generic_analysis_workflow(
  proposal : JobProposal,
  now_ms : Int,
  cwd : String,
  home : String,
  workspace_root : String,
  family : String,
  template : String,
  capabilities : Array[String],
) -> ProposalCompilation {
  let template_skills = selected_template_skills(template)
  let notes = compiler_notes_for_selection(
    proposal, family, template, template, capabilities, false,
  )
  let job_id = "job.proposal.\{proposal.id}"
  let workflow_id = "workflow.proposal.\{proposal.id}"
  let steps = proposal.steps.map(fn(step) {
    WorkflowStepDefinition::{
      id: step.id,
      kind: step.kind,
      config: AnalysisStepConfig::new(
        prompt=step.prompt,
        cwd=Some(cwd),
        home=Some(home),
        workspace=Some(workspace_root),
        preferred_skills=template_skills,
        enable_tools=true,
        web_search=false,
        policy=AnalysisPolicy::new(skip_if_artifact_exists=false),
        artifacts=AnalysisArtifactConfig::new(
          report_artifact_type="job.proposal.step.report",
          result_artifact_type="job.proposal.step.result",
          logical_key=Some("\{proposal.id}:\{step.id}"),
          scope=["jobs", "proposal:\{proposal.id}"],
          append_only=false,
        ),
        metadata={
          "proposal_id": proposal.id,
          "proposal_step_id": step.id,
          "proposal_step_title": step.title,
          "family": family,
          "template": template,
        },
      ).to_json(),
      retry_policy: None,
    }
  })
  let definition = JobDefinition::{
    id: job_id,
    kind: "job.proposal",
    enabled: true,
    config: {
      "proposal_id": proposal.id,
      "workspace": workspace_root,
      "family": family,
      "template": template,
      "required_capabilities": capabilities,
      "missing_capabilities": missing_capabilities(capabilities),
      "compiler_notes": notes,
      "notify": {
        "channel": proposal.channel_id,
        "account_id": proposal.account_id,
        "to": proposal.recipient,
        "thread_id": proposal.thread_id,
        "heartbeat_interval_ms": 120000,
        "warn_after_ms": 300000,
      },
    },
    schedule: None,
    retry_policy: None,
    workflow_id: Some(workflow_id),
    created_at: now_ms,
    updated_at: now_ms,
    tags: proposal.tags,
  }
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: "job.proposal",
    steps,
    output_bindings: proposal.steps.map(fn(step) { step.id }),
  }
  ProposalCompilation::{
    family,
    template,
    required_capabilities: capabilities,
    missing_capabilities: missing_capabilities(capabilities),
    compiler_notes: notes,
    definition,
    workflow,
    bindings: [],
  }
}

///|
fn compile_research_workflow(
  proposal : JobProposal,
  now_ms : Int,
  cwd : String,
  home : String,
  workspace_root : String,
  template : String,
  capabilities : Array[String],
) -> ProposalCompilation {
  let template_skills = selected_template_skills(template)
  let notes = compiler_notes_for_selection(
    proposal, "research", template, template, capabilities, false,
  )
  let job_id = "job.proposal.\{proposal.id}"
  let workflow_id = "workflow.proposal.\{proposal.id}"
  let topic_id = inferred_research_topic_id(proposal)
  let query = inferred_research_query(proposal)
  let sync_step = WorkflowStepDefinition::{
    id: proposal.steps.get(0).map(fn(step) { step.id }).unwrap_or("sync"),
    kind: "research.topic.sync",
    config: ResearchTopicSyncConfig::new(
      topic_id~,
      query~,
      title=Some(proposal.title),
      max_results=12,
      download_pdf=true,
      scope=["jobs", "proposal:\{proposal.id}", research_topic_scope(topic_id)],
    ).to_json(),
    retry_policy: Some(RetryPolicy::{
      max_attempts: 2,
      backoff_ms: Some(60_000),
    }),
  }
  let summarize_step = WorkflowStepDefinition::{
    id: proposal.steps.get(1).map(fn(step) { step.id }).unwrap_or("summarize"),
    kind: "job.analysis",
    config: AnalysisStepConfig::new(
      prompt=proposal.steps
        .get(1)
        .map(fn(step) { step.prompt })
        .unwrap_or(default_research_summary_prompt(proposal, topic_id)),
      cwd=Some(cwd),
      home=Some(home),
      workspace=Some(workspace_root),
      preferred_skills=template_skills,
      enable_tools=true,
      web_search=false,
      policy=AnalysisPolicy::new(skip_if_artifact_exists=false),
      artifacts=AnalysisArtifactConfig::new(
        report_artifact_type="research.topic.summary.report",
        result_artifact_type="research.topic.summary.result",
        logical_key=Some("\{proposal.id}:summary"),
        scope=[
          "jobs",
          "proposal:\{proposal.id}",
          research_scope(),
          research_topic_scope(topic_id),
        ],
        append_only=false,
      ),
      metadata={
        "proposal_id": proposal.id,
        "family": "research",
        "template": template,
        "topic_id": topic_id,
      },
    ).to_json(),
    retry_policy: None,
  }
  let report_step = WorkflowStepDefinition::{
    id: proposal.steps.get(2).map(fn(step) { step.id }).unwrap_or("deliver"),
    kind: "job.analysis",
    config: AnalysisStepConfig::new(
      prompt=proposal.steps
        .get(2)
        .map(fn(step) { step.prompt })
        .unwrap_or(default_research_report_prompt(proposal)),
      cwd=Some(cwd),
      home=Some(home),
      workspace=Some(workspace_root),
      preferred_skills=template_skills,
      enable_tools=true,
      web_search=false,
      policy=AnalysisPolicy::new(skip_if_artifact_exists=false),
      artifacts=AnalysisArtifactConfig::new(
        report_artifact_type="research.topic.report",
        result_artifact_type="research.topic.report.result",
        logical_key=Some("\{proposal.id}:report"),
        scope=[
          "jobs",
          "proposal:\{proposal.id}",
          research_scope(),
          research_topic_scope(topic_id),
        ],
        append_only=false,
      ),
      metadata={
        "proposal_id": proposal.id,
        "family": "research",
        "template": template,
        "topic_id": topic_id,
      },
    ).to_json(),
    retry_policy: None,
  }
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: "job.proposal.research",
    steps: [sync_step, summarize_step, report_step],
    output_bindings: [sync_step.id, summarize_step.id, report_step.id],
  }
  let definition = JobDefinition::{
    id: job_id,
    kind: "job.proposal.research",
    enabled: true,
    config: {
      "proposal_id": proposal.id,
      "workspace": workspace_root,
      "family": "research",
      "template": template,
      "topic_id": topic_id,
      "query": query,
      "required_capabilities": capabilities,
      "missing_capabilities": missing_capabilities(capabilities),
      "compiler_notes": notes,
      "notify": {
        "channel": proposal.channel_id,
        "account_id": proposal.account_id,
        "to": proposal.recipient,
        "thread_id": proposal.thread_id,
        "heartbeat_interval_ms": 120000,
        "warn_after_ms": 300000,
      },
    },
    schedule: None,
    retry_policy: Some(RetryPolicy::{
      max_attempts: 2,
      backoff_ms: Some(60_000),
    }),
    workflow_id: Some(workflow_id),
    created_at: now_ms,
    updated_at: now_ms,
    tags: [..proposal.tags, "research", topic_id],
  }
  ProposalCompilation::{
    family: "research",
    template,
    required_capabilities: capabilities,
    missing_capabilities: missing_capabilities(capabilities),
    compiler_notes: notes,
    definition,
    workflow,
    bindings: [
      research_topic_binding(topic_id, now_ms, title=Some(proposal.title)),
    ],
  }
}

///|
fn delegate_step_from_proposal_step(
  proposal : JobProposal,
  step : JobProposalStep,
  cwd : String,
  home : String,
  workspace_root : String,
) -> WorkflowStepDefinition {
  WorkflowStepDefinition::{
    id: step.id,
    kind: "job.delegate",
    config: SubjobStepConfig::new(
      request_text=[
        step.title,
        step.prompt,
        "Parent request: \{proposal.request_text}",
        "Workspace root: \{workspace_root}",
      ].join("\n\n"),
      cwd=Some(cwd),
      home=Some(home),
      include_parent_outputs=true,
      max_depth=2,
    ).to_json(),
    retry_policy: Some(RetryPolicy::{ max_attempts: 1, backoff_ms: Some(0) }),
  }
}

///|
fn compile_delegated_generic_workflow(
  proposal : JobProposal,
  now_ms : Int,
  cwd : String,
  home : String,
  workspace_root : String,
  family : String,
  template : String,
  capabilities : Array[String],
) -> ProposalCompilation {
  let notes = compiler_notes_for_selection(
    proposal, family, template, template, capabilities, true,
  )
  let job_id = "job.proposal.\{proposal.id}"
  let workflow_id = "workflow.proposal.\{proposal.id}"
  let delegate_steps = proposal.steps.map(fn(step) {
    delegate_step_from_proposal_step(proposal, step, cwd, home, workspace_root)
  })
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: "job.proposal.delegated",
    steps: delegate_steps,
    output_bindings: delegate_steps.map(fn(step) { step.id }),
  }
  let definition = JobDefinition::{
    id: job_id,
    kind: "job.proposal.delegated",
    enabled: true,
    config: {
      "proposal_id": proposal.id,
      "workspace": workspace_root,
      "family": family,
      "template": template,
      "required_capabilities": capabilities,
      "missing_capabilities": missing_capabilities(capabilities),
      "compiler_notes": notes,
      "notify": {
        "channel": proposal.channel_id,
        "account_id": proposal.account_id,
        "to": proposal.recipient,
        "thread_id": proposal.thread_id,
        "heartbeat_interval_ms": 120000,
        "warn_after_ms": 300000,
      },
    },
    schedule: None,
    retry_policy: Some(RetryPolicy::{ max_attempts: 1, backoff_ms: Some(0) }),
    workflow_id: Some(workflow_id),
    created_at: now_ms,
    updated_at: now_ms,
    tags: [..proposal.tags, "delegated"],
  }
  ProposalCompilation::{
    family,
    template,
    required_capabilities: capabilities,
    missing_capabilities: missing_capabilities(capabilities),
    compiler_notes: notes,
    definition,
    workflow,
    bindings: [],
  }
}

///|
fn compile_delegated_research_workflow(
  proposal : JobProposal,
  now_ms : Int,
  cwd : String,
  home : String,
  workspace_root : String,
  template : String,
  capabilities : Array[String],
) -> ProposalCompilation {
  let topic_id = inferred_research_topic_id(proposal)
  let query = inferred_research_query(proposal)
  let template_skills = selected_template_skills(template)
  let preferred_skill_names = template_skills.join(", ")
  let notes = compiler_notes_for_selection(
    proposal, "research", template, template, capabilities, true,
  )
  let job_id = "job.proposal.\{proposal.id}"
  let workflow_id = "workflow.proposal.\{proposal.id}"
  let sync_step = WorkflowStepDefinition::{
    id: proposal.steps.get(0).map(fn(step) { step.id }).unwrap_or("sync"),
    kind: "research.topic.sync",
    config: ResearchTopicSyncConfig::new(
      topic_id~,
      query~,
      title=Some(proposal.title),
      max_results=12,
      download_pdf=true,
      scope=["jobs", "proposal:\{proposal.id}", research_topic_scope(topic_id)],
    ).to_json(),
    retry_policy: Some(RetryPolicy::{
      max_attempts: 2,
      backoff_ms: Some(60_000),
    }),
  }
  let delegated_steps = proposal.steps[1:].map(fn(step) {
    WorkflowStepDefinition::{
      ..delegate_step_from_proposal_step(
        proposal, step, cwd, home, workspace_root,
      ),
      config: SubjobStepConfig::new(
        request_text=[
          step.title,
          step.prompt,
          "Use topic context `\{topic_id}` and existing research artifacts when available.",
          "Preferred skills: \{preferred_skill_names}",
          "Workspace root: \{workspace_root}",
        ].join("\n\n"),
        cwd=Some(cwd),
        home=Some(home),
        include_parent_outputs=true,
        max_depth=2,
      ).to_json(),
    }
  })
  let steps = [sync_step, ..delegated_steps]
  let workflow = WorkflowDefinition::{
    id: workflow_id,
    kind: "job.proposal.research.delegated",
    steps,
    output_bindings: steps.map(fn(step) { step.id }),
  }
  let definition = JobDefinition::{
    id: job_id,
    kind: "job.proposal.research.delegated",
    enabled: true,
    config: {
      "proposal_id": proposal.id,
      "workspace": workspace_root,
      "family": "research",
      "template": template,
      "topic_id": topic_id,
      "query": query,
      "required_capabilities": capabilities,
      "missing_capabilities": missing_capabilities(capabilities),
      "compiler_notes": notes,
      "notify": {
        "channel": proposal.channel_id,
        "account_id": proposal.account_id,
        "to": proposal.recipient,
        "thread_id": proposal.thread_id,
        "heartbeat_interval_ms": 120000,
        "warn_after_ms": 300000,
      },
    },
    schedule: None,
    retry_policy: Some(RetryPolicy::{
      max_attempts: 2,
      backoff_ms: Some(60_000),
    }),
    workflow_id: Some(workflow_id),
    created_at: now_ms,
    updated_at: now_ms,
    tags: [..proposal.tags, "research", topic_id, "delegated"],
  }
  ProposalCompilation::{
    family: "research",
    template,
    required_capabilities: capabilities,
    missing_capabilities: missing_capabilities(capabilities),
    compiler_notes: notes,
    definition,
    workflow,
    bindings: [
      research_topic_binding(topic_id, now_ms, title=Some(proposal.title)),
    ],
  }
}

///|
pub fn infer_proposal_compilation_hints(
  proposal : JobProposal,
) -> (String, String, Array[String]) {
  let (family, template, capabilities, _, _) = explain_proposal_compilation_hints(
    proposal,
  )
  (family, template, capabilities)
}

///|
pub fn compile_job_proposal(
  proposal : JobProposal,
  now_ms : Int,
  cwd : String,
  home : String,
  workspace_root? : String = cwd,
) -> ProposalCompilation {
  let (family, template, capabilities) = infer_proposal_compilation_hints(
    proposal,
  )
  let should_delegate = proposal_should_delegate(proposal, family, capabilities)
  let resolved_template = select_compilation_template(
    proposal, family, template, capabilities, should_delegate,
  )
  match family {
    "research" if resolved_template == "research.delegated_review" =>
      compile_delegated_research_workflow(
        proposal, now_ms, cwd, home, workspace_root, resolved_template, capabilities,
      )
    "research" =>
      compile_research_workflow(
        proposal, now_ms, cwd, home, workspace_root, resolved_template, capabilities,
      )
    _ if resolved_template == "generic.delegated" =>
      compile_delegated_generic_workflow(
        proposal, now_ms, cwd, home, workspace_root, family, resolved_template, capabilities,
      )
    _ =>
      compile_generic_analysis_workflow(
        proposal, now_ms, cwd, home, workspace_root, family, resolved_template, capabilities,
      )
  }
}
