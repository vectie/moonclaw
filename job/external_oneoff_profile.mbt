///|
/// Apply the exact already-loaded profile bound by the one-off receipt. Looking
/// it up a second time by family can select another configured profile ID, or
/// reread changed config. Ordinary family-based imports remain unchanged.
fn apply_oneoff_profile(
  proposal : JobProposal,
  profile : JobProfile,
  workspace_root : String,
) -> JobProposal {
  if profile.steps.is_empty() {
    return proposal
  }
  let steps = profile.steps.map(step => {
    let prompt_source = if step.kind == "job.delegate" {
      step.request_template.unwrap_or(proposal.request_text)
    } else {
      step.prompt_template.unwrap_or(proposal.request_text)
    }
    JobProposalStep::{
      id: step.id,
      title: step.title,
      kind: step.kind,
      metadata: step.metadata.unwrap_or({}),
      child_profile: step.child_profile,
      execution_mode: step.execution_mode,
      execution_target: step.execution_target,
      include_parent_outputs: step.include_parent_outputs,
      max_depth: step.max_depth,
      prompt: render_profile_step_template(
        prompt_source,
        proposal,
        profile.family,
        workspace_root,
      ),
    }
  })
  {
    ..proposal,
    suggested_family: Some(profile.family),
    profile_id: Some(profile.id),
    profile_role: profile.role,
    profile_metadata: merge_json_metadata(
      proposal.profile_metadata,
      profile.metadata,
    ),
    steps,
    tags: [..proposal.tags, ..profile.tags],
  }
}
