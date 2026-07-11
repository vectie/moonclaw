///|
fn evidence_dossier(
  primary_artifact? : String = "raw/primary.md",
  secondary_artifact? : String = "raw/secondary.md",
) -> EvidenceDossier {
  {
    contract_id: "moonsuite.evidence-dossier.v1",
    task_id: "task-1",
    question: "What is known?",
    policy: {
      minimum_sources: 2,
      minimum_primary_sources: 1,
      minimum_evidence_per_claim: 1,
      require_open_questions: true,
    },
    sources: [
      {
        source_id: "source-primary",
        locator: "https://example.test/primary",
        authority_class: "primary",
        retrieved_at: "2026-07-11T00:00:00Z",
        artifact_ref: primary_artifact,
      },
      {
        source_id: "source-secondary",
        locator: "https://example.test/secondary",
        authority_class: "secondary",
        retrieved_at: "2026-07-11T00:00:00Z",
        artifact_ref: secondary_artifact,
      },
    ],
    claims: [
      {
        claim_id: "claim-1",
        statement: "A bounded claim",
        source_ids: ["source-primary"],
        confidence: "high",
      },
    ],
    open_questions: ["What should be tested next?"],
    output_artifacts: ["outputs/dossier.md"],
  }
}

///|
test "MoonClaw accepts a dossier that satisfies its declared policy" {
  let receipt = validate_dossier(evidence_dossier())
  assert_true(receipt.accepted)
  assert_eq(receipt.primary_source_count, 1)
}

///|
test "MoonClaw fails closed when claims cite unknown evidence" {
  let dossier = evidence_dossier()
  dossier.claims[0].source_ids.clear()
  dossier.claims[0].source_ids.push("missing")
  let receipt = validate_dossier(dossier)
  assert_false(receipt.accepted)
  assert_true(receipt.blockers.length() > 0)
}

///|
async test "MoonClaw workspace validation requires local evidence artifacts" {
  let dossier = evidence_dossier(
    primary_artifact="evidence/evidence.mbt",
    secondary_artifact="evidence/evidence_wbtest.mbt",
  )
  let accepted = validate_dossier_in_workspace(dossier, ".")
  assert_true(accepted.accepted)
  let missing = validate_dossier_in_workspace(
    evidence_dossier(
      primary_artifact="evidence/does-not-exist.md",
      secondary_artifact="evidence/evidence_wbtest.mbt",
    ),
    ".",
  )
  assert_false(missing.accepted)
  assert_true(
    missing.blockers.any(blocker => blocker.contains("does not exist")),
  )
}

///|
async test "MoonClaw workspace validation rejects escaping evidence refs" {
  let dossier = evidence_dossier(
    primary_artifact="../outside.md",
    secondary_artifact="/tmp/outside.md",
  )
  let receipt = validate_dossier_in_workspace(dossier, ".")
  assert_false(receipt.accepted)
  assert_true(
    receipt.blockers.any(blocker => blocker.contains("must stay relative")),
  )
}
