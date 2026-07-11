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

///|
fn has_parent_escape(path : String) -> Bool {
  let normalized = path.replace(old="\\", new="/")
  normalized.split("/").any(segment => segment == "..")
}

///|
fn receipt_with_blockers(
  receipt : EvidenceQualityReceipt,
  blockers : Array[String],
) -> EvidenceQualityReceipt {
  {
    contract_id: receipt.contract_id,
    task_id: receipt.task_id,
    accepted: blockers.is_empty(),
    source_count: receipt.source_count,
    primary_source_count: receipt.primary_source_count,
    claim_count: receipt.claim_count,
    blockers,
    output_artifacts: receipt.output_artifacts,
  }
}

///|
/// Validate both dossier semantics and the local evidence artifacts it cites.
///
/// Every `artifact_ref` must be book-relative, exist, and resolve inside the
/// canonical book root. Remote source locators remain valid provenance, but
/// they do not replace a locally tracked retrieval artifact.
pub async fn validate_dossier_in_workspace(
  dossier : EvidenceDossier,
  book_root : String,
) -> EvidenceQualityReceipt {
  let receipt = validate_dossier(dossier)
  let blockers : Array[String] = []
  blockers.push_iter(receipt.blockers.iter())
  let trimmed_root = book_root.trim().to_owned()
  if trimmed_root.is_empty() || !@fsx.exists(trimmed_root) {
    blockers.push("evidence book root does not exist")
    return receipt_with_blockers(receipt, blockers)
  }
  let canonical_root = @fsx.resolve(trimmed_root) catch {
    _ => {
      blockers.push("evidence book root cannot be resolved")
      return receipt_with_blockers(receipt, blockers)
    }
  }
  for source in dossier.sources {
    let artifact_ref = source.artifact_ref.trim().to_owned()
    if artifact_ref.is_empty() {
      continue
    }
    if @pathx.is_absolute(artifact_ref) || has_parent_escape(artifact_ref) {
      blockers.push(
        "source " +
        source.source_id +
        " artifact_ref must stay relative to the evidence book",
      )
      continue
    }
    let artifact_path = @pathx.join(trimmed_root, artifact_ref)
    if !@fsx.exists(artifact_path) {
      blockers.push(
        "source " + source.source_id + " artifact_ref does not exist",
      )
      continue
    }
    let canonical_artifact = @fsx.resolve(artifact_path) catch {
      _ => {
        blockers.push(
          "source " + source.source_id + " artifact_ref cannot be resolved",
        )
        continue
      }
    }
    if canonical_artifact != canonical_root &&
      !canonical_artifact.has_prefix(canonical_root + "/") {
      blockers.push(
        "source " +
        source.source_id +
        " artifact_ref resolves outside the evidence book",
      )
    }
  }
  receipt_with_blockers(receipt, blockers)
}
