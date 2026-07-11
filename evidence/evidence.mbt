///|
pub(all) struct EvidencePolicy {
  minimum_sources : Int
  minimum_primary_sources : Int
  minimum_evidence_per_claim : Int
  require_open_questions : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EvidenceSource {
  source_id : String
  locator : String
  authority_class : String
  retrieved_at : String
  artifact_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EvidenceClaim {
  claim_id : String
  statement : String
  source_ids : Array[String]
  confidence : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EvidenceDossier {
  contract_id : String
  task_id : String
  question : String
  policy : EvidencePolicy
  sources : Array[EvidenceSource]
  claims : Array[EvidenceClaim]
  open_questions : Array[String]
  output_artifacts : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct EvidenceQualityReceipt {
  contract_id : String
  task_id : String
  accepted : Bool
  source_count : Int
  primary_source_count : Int
  claim_count : Int
  blockers : Array[String]
  output_artifacts : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
fn source_exists(sources : Array[EvidenceSource], source_id : String) -> Bool {
  sources.any(source => source.source_id == source_id)
}

///|
pub fn validate_dossier(dossier : EvidenceDossier) -> EvidenceQualityReceipt {
  let blockers : Array[String] = []
  if dossier.contract_id != "moonsuite.evidence-dossier.v1" {
    blockers.push("unsupported evidence dossier contract")
  }
  if dossier.task_id.trim().is_empty() || dossier.question.trim().is_empty() {
    blockers.push("task identity and question are required")
  }
  if dossier.policy.minimum_sources < 1 ||
    dossier.policy.minimum_primary_sources < 0 ||
    dossier.policy.minimum_evidence_per_claim < 1 {
    blockers.push("evidence policy thresholds are invalid")
  }
  let primary_count = dossier.sources
    .filter(source => source.authority_class == "primary")
    .length()
  if dossier.sources.length() < dossier.policy.minimum_sources {
    blockers.push("source count is below policy minimum")
  }
  if primary_count < dossier.policy.minimum_primary_sources {
    blockers.push("primary source count is below policy minimum")
  }
  if dossier.claims.is_empty() {
    blockers.push("dossier has no claims")
  }
  if dossier.output_artifacts.is_empty() {
    blockers.push("dossier has no output artifacts")
  }
  if dossier.policy.require_open_questions && dossier.open_questions.is_empty() {
    blockers.push("dossier does not declare remaining information gaps")
  }
  for source in dossier.sources {
    if source.source_id.trim().is_empty() ||
      source.locator.trim().is_empty() ||
      source.retrieved_at.trim().is_empty() ||
      source.artifact_ref.trim().is_empty() {
      blockers.push(
        "source records require identity, locator, retrieval time, and artifact",
      )
    }
    if source.authority_class != "primary" &&
      source.authority_class != "secondary" {
      blockers.push("source authority class must be primary or secondary")
    }
  }
  for claim in dossier.claims {
    if claim.claim_id.trim().is_empty() || claim.statement.trim().is_empty() {
      blockers.push("claims require identity and statement")
    }
    if claim.source_ids.length() < dossier.policy.minimum_evidence_per_claim {
      blockers.push("claim " + claim.claim_id + " has insufficient evidence")
    }
    for source_id in claim.source_ids {
      if !source_exists(dossier.sources, source_id) {
        blockers.push(
          "claim " + claim.claim_id + " cites unknown source " + source_id,
        )
      }
    }
  }
  {
    contract_id: "moonsuite.evidence-quality-receipt.v1",
    task_id: dossier.task_id,
    accepted: blockers.is_empty(),
    source_count: dossier.sources.length(),
    primary_source_count: primary_count,
    claim_count: dossier.claims.length(),
    blockers,
    output_artifacts: dossier.output_artifacts,
  }
}
