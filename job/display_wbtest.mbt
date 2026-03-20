///|
test "human readable ids include slug and short suffix" {
  let proposal_id = human_readable_proposal_id(
    "Track recent VLA papers on arXiv", 1_710_900_000, "abc12345-6789",
  )
  inspect(proposal_id.contains("-track-recent-vla-papers-on-"), content="true")
  inspect(proposal_id.has_suffix("abc123"), content="true")

  let run_id = human_readable_run_id(1_710_900_000, "def67890-1234")
  inspect(run_id.has_prefix("run-"), content="true")
  inspect(run_id.has_suffix("def678"), content="true")
}

///|
test "definition_display_title prefers stored title" {
  let definition = JobDefinition::{
    id: "job.proposal.opaque",
    kind: "job.proposal",
    enabled: true,
    config: { "title": "Fetch Top 10 VLA Articles from arXiv" },
    schedule: None,
    retry_policy: None,
    workflow_id: None,
    created_at: 1,
    updated_at: 1,
    tags: [],
  }
  inspect(
    definition_display_title(definition),
    content="Fetch Top 10 VLA Articles from arXiv",
  )
}

///|
test "unwrapped_epoch_ms_near restores wrapped timestamps near current era" {
  let restored = unwrapped_epoch_ms_near(183505038, 1_742_801_777_334L)
  inspect(restored > 1_700_000_000_000L, content="true")
  inspect(restored < 1_800_000_000_000L, content="true")
}
