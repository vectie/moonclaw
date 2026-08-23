///|
pub(all) struct GoalRunRequirementResult {
  id : String
  passed : Bool
} derive(Eq, Debug)

///|
pub(all) struct GoalRunResult {
  runner : String
  checkpoint : Int
  completed : Bool
  verification_passed : Bool
  requirements : Array[GoalRunRequirementResult]
  artifact_digest : String
  summary : String
} derive(Eq, Debug)

///|
pub(all) enum GoalComparisonVerdict {
  Equivalent
  Similar
  Diverged
  Insufficient
} derive(Eq, Debug)

///|
pub(all) struct GoalComparison {
  checkpoint : Int
  verdict : GoalComparisonVerdict
  exact_invariants_match : Bool
  lexical_similarity_bps : Int
  mismatches : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct GoalComparisonTrend {
  sample_count : Int
  equivalent_count : Int
  similar_count : Int
  diverged_count : Int
  insufficient_count : Int
  average_similarity_bps : Int
  stable : Bool
} derive(Eq, Debug)

///|
fn goal_comparison_normalize(text : String) -> String {
  let output = StringBuilder::new()
  let mut pending_space = false
  let mut has_output = false
  for char in text {
    let code = char.to_int()
    let normalized = if code >= 65 && code <= 90 { code + 32 } else { code }
    if (normalized >= 97 && normalized <= 122) ||
      (normalized >= 48 && normalized <= 57) {
      if pending_space && has_output {
        output.write_char(' ')
      }
      output.write_char(normalized.unsafe_to_char())
      has_output = true
      pending_space = false
    } else {
      pending_space = true
    }
  }
  output.to_string()
}

///|
fn goal_comparison_unique_tokens(normalized : String) -> Array[String] {
  let result : Array[String] = []
  for token_view in normalized.split(" ") {
    let token = token_view.to_owned()
    if token != "" && !result.contains(token) {
      result.push(token)
    }
  }
  result
}

///|
fn goal_comparison_lexical_similarity_bps(left : String, right : String) -> Int {
  let left_tokens = goal_comparison_unique_tokens(
    goal_comparison_normalize(left),
  )
  let right_tokens = goal_comparison_unique_tokens(
    goal_comparison_normalize(right),
  )
  if left_tokens.length() == 0 && right_tokens.length() == 0 {
    10000
  } else if left_tokens.length() == 0 || right_tokens.length() == 0 {
    0
  } else {
    let mut intersection = 0
    for token in left_tokens {
      if right_tokens.contains(token) {
        intersection += 1
      }
    }
    2 * intersection * 10000 / (left_tokens.length() + right_tokens.length())
  }
}

///|
fn goal_comparison_requirements_valid(
  items : Array[GoalRunRequirementResult],
) -> Bool {
  if items.length() == 0 {
    return false
  }
  let ids : Array[String] = []
  for item in items {
    let normalized = item.id.trim()
    if normalized == "" || normalized != item.id || ids.contains(item.id) {
      return false
    }
    ids.push(item.id)
  }
  true
}

///|
fn goal_comparison_requirements_match(
  left : Array[GoalRunRequirementResult],
  right : Array[GoalRunRequirementResult],
) -> Bool {
  if !goal_comparison_requirements_valid(left) ||
    !goal_comparison_requirements_valid(right) ||
    left.length() != right.length() {
    return false
  }
  for left_item in left {
    let mut found = false
    for right_item in right {
      if left_item.id == right_item.id && left_item.passed == right_item.passed {
        found = true
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
fn goal_comparison_result_valid(result : GoalRunResult) -> Bool {
  result.runner != "" &&
  result.runner.trim() == result.runner &&
  result.checkpoint >= 0 &&
  result.artifact_digest != "" &&
  result.artifact_digest.trim() == result.artifact_digest &&
  result.summary.trim() != "" &&
  goal_comparison_requirements_valid(result.requirements)
}

///|
pub fn goal_comparison_compare(
  reference : GoalRunResult,
  candidate : GoalRunResult,
  similarity_threshold_bps : Int,
) -> GoalComparison {
  let mismatches : Array[String] = []
  let threshold_valid = similarity_threshold_bps >= 0 &&
    similarity_threshold_bps <= 10000
  let reference_valid = goal_comparison_result_valid(reference)
  let candidate_valid = goal_comparison_result_valid(candidate)
  let checkpoint_match = reference.checkpoint >= 0 &&
    candidate.checkpoint >= 0 &&
    reference.checkpoint == candidate.checkpoint
  if !threshold_valid {
    mismatches.push("threshold.invalid")
  }
  if !reference_valid {
    mismatches.push("reference.invalid")
  }
  if !candidate_valid {
    mismatches.push("candidate.invalid")
  }
  if !checkpoint_match {
    mismatches.push("checkpoint.mismatch")
  }
  let sufficient = threshold_valid &&
    reference_valid &&
    candidate_valid &&
    checkpoint_match
  if !sufficient {
    return {
      checkpoint: if checkpoint_match {
        reference.checkpoint
      } else {
        -1
      },
      verdict: Insufficient,
      exact_invariants_match: false,
      lexical_similarity_bps: 0,
      mismatches,
    }
  }
  let completion_match = reference.completed == candidate.completed
  let verification_match = reference.verification_passed ==
    candidate.verification_passed
  let requirements_match = goal_comparison_requirements_match(
    reference.requirements,
    candidate.requirements,
  )
  let digest_match = reference.artifact_digest == candidate.artifact_digest
  let normalized_reference = goal_comparison_normalize(reference.summary)
  let normalized_candidate = goal_comparison_normalize(candidate.summary)
  let summary_match = normalized_reference == normalized_candidate
  if !completion_match {
    mismatches.push("completion.mismatch")
  }
  if !verification_match {
    mismatches.push("verification.mismatch")
  }
  if !requirements_match {
    mismatches.push("requirements.mismatch")
  }
  if !digest_match {
    mismatches.push("artifact_digest.mismatch")
  }
  if !summary_match {
    mismatches.push("summary.mismatch")
  }
  let exact_invariants_match = completion_match &&
    verification_match &&
    requirements_match &&
    digest_match
  let lexical_similarity_bps = goal_comparison_lexical_similarity_bps(
    reference.summary,
    candidate.summary,
  )
  let verdict = if exact_invariants_match && summary_match {
    Equivalent
  } else if exact_invariants_match &&
    lexical_similarity_bps >= similarity_threshold_bps {
    Similar
  } else {
    Diverged
  }
  {
    checkpoint: reference.checkpoint,
    verdict,
    exact_invariants_match,
    lexical_similarity_bps,
    mismatches,
  }
}

///|
pub fn goal_comparison_trend(
  comparisons : Array[GoalComparison],
) -> GoalComparisonTrend {
  let mut equivalent_count = 0
  let mut similar_count = 0
  let mut diverged_count = 0
  let mut insufficient_count = 0
  let mut similarity_total : Int64 = 0
  for comparison in comparisons {
    match comparison.verdict {
      Equivalent => equivalent_count += 1
      Similar => similar_count += 1
      Diverged => diverged_count += 1
      Insufficient => insufficient_count += 1
    }
    similarity_total += comparison.lexical_similarity_bps.to_int64()
  }
  let sample_count = comparisons.length()
  let average_similarity_bps = if sample_count == 0 {
    0
  } else {
    (similarity_total / sample_count.to_int64()).to_int()
  }
  {
    sample_count,
    equivalent_count,
    similar_count,
    diverged_count,
    insufficient_count,
    average_similarity_bps,
    stable: sample_count > 0 && diverged_count == 0 && insufficient_count == 0,
  }
}
