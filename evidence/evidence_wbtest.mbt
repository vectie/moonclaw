///|
fn evidence_dossier() -> EvidenceDossier {
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
        artifact_ref: "raw/primary.md",
      },
      {
        source_id: "source-secondary",
        locator: "https://example.test/secondary",
        authority_class: "secondary",
        retrieved_at: "2026-07-11T00:00:00Z",
        artifact_ref: "raw/secondary.md",
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
