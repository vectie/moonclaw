///|
fn option(args : Array[String], flag : String) -> String? {
  for index in 0..<(args.length() - 1) {
    if args[index] == flag {
      return Some(args[index + 1])
    }
  }
  None
}

///|
fn required_option(args : Array[String], flag : String) -> String raise {
  match option(args, flag) {
    Some(value) if !value.trim().is_empty() => value
    _ => fail("MoonClaw flow adapter requires \{flag}")
  }
}

///|
fn repeated_option(args : Array[String], flag : String) -> Array[String] {
  let values : Array[String] = []
  for index in 0..<(args.length() - 1) {
    if args[index] == flag {
      values.push(args[index + 1])
    }
  }
  values
}

///|
fn safe_ref(reference : String) -> Bool {
  let value = reference.trim().replace(old="\\", new="/")
  !value.is_empty() &&
  !value.has_prefix("/") &&
  !value.split("/").any(part => part.is_empty() || part == "..")
}

///|
fn require_ref(reference : String, label : String) -> String raise {
  if !safe_ref(reference) {
    fail("MoonClaw flow adapter \{label} must be workspace-relative")
  }
  reference
}

///|
fn require_segment(value : String, label : String) -> String raise {
  let segment = value.trim().to_owned()
  if !safe_ref(segment) || segment.contains("/") || segment == "." {
    fail("MoonClaw flow adapter " + label + " must be a safe path segment")
  }
  segment
}

///|
fn flow_attempt_root(
  workspace : String,
  run_id : String,
  attempt_id : String,
) -> String raise {
  workspace +
  "/.moonsuite/products/moonclaw/flow/" +
  require_segment(run_id, "run_id") +
  "/" +
  require_segment(attempt_id, "attempt_id")
}

///|
async fn read_json(path : String) -> Json {
  @json.parse(@fsx.read_file(path))
}

///|
async fn write_json(path : String, value : Json) -> Unit {
  @fsx.make_directory(@pathx.dirname(path), recursive=true, exists_ok=true)
  @fsx.write_to_file(path, value.stringify(indent=2) + "\n", create=0o644)
}

///|
fn string_field(fields : Map[String, Json], key : String) -> String raise {
  match fields.get(key) {
    Some(String(value)) if !value.trim().is_empty() => value
    _ => fail("MoonClaw flow request requires \{key}")
  }
}

///|
fn object(value : Json, label : String) -> Map[String, Json] raise {
  match value {
    Object(fields) => fields
    _ => fail("MoonClaw \{label} must be a JSON object")
  }
}

///|
fn non_empty_field(fields : Map[String, Json], key : String) -> Bool {
  match fields.get(key) {
    Some(String(value)) => !value.trim().is_empty()
    Some(Array(values)) => !values.is_empty()
    Some(Object(values)) => !values.is_empty()
    Some(Number(_)) => true
    Some(True | False) => true
    _ => false
  }
}

///|
fn web_provenance_issues(fields : Map[String, Json]) -> Array[String] {
  let issues : Array[String] = []
  guard fields.get("web_provenance") is Some(Array(events)) else {
    return ["MoonWiki evidence requires wrapper-owned web_provenance"]
  }
  let mut searched = false
  let mut fetched = false
  for event in events {
    guard event is Object(entry) else { continue }
    let succeeded = entry.get("succeeded") == Some(Json::boolean(true))
    match entry.get("tool") {
      Some(String("web_search")) if succeeded => searched = true
      Some(String("web_fetch")) if succeeded => fetched = true
      _ => ()
    }
  }
  if !searched {
    issues.push("MoonWiki evidence requires a successful governed web_search")
  }
  if !fetched {
    issues.push("MoonWiki evidence requires a successful governed web_fetch")
  }
  issues
}

///|
fn contract_guidance(request : Json) -> String {
  let fields = object(request, "flow request") catch { _ => return "" }
  let contract = match fields.get("output_contracts") {
    Some(Array([String(value), ..])) => value
    _ => return ""
  }
  match contract {
    "moonwiki.evidence-bundle.v1" =>
      "Required product contract: use the governed web_search tool to discover public source leads and web_fetch to read every source you cite. The wrapper will attach immutable tool provenance; invented or unfetched locators are rejected. Return sources[] with unique source_id/title/locator/authority/accessed_at; claims[] with statement/source_refs/confidence 0..1; non-empty contradictions[], limitations[], remaining_information_gaps[], query_lineage[]; and stopping_rationale. A 'none found' contradiction must still record how it was checked."
    "moontown.deliberation.v1" =>
      "Required product contract: civic_round is exactly a moontown.autonomous-civic-round.v1 object with round_id, commission_id, question, commissioned_agenda_ids, requested_authority, and recorded_at. Include non-empty comparison_criteria objects with criterion_id, name, and definition so rankings remain independently interpretable. Include comparison_assessments covering every contribution_id/criterion_id pair; each assessment needs a non-empty rating, rationale, and evidence_refs. Also include non-empty unresolved_assumptions strings preserved by the recommendation. It needs at least two contributions; every contribution requires contribution_id, participant_id, source_book_id, origin (commissioned/emergent/dissenting/minority/synthesized), summary, evidence_refs, alternatives, blockers, implementation_criteria, claim_ceiling (observation/research-evidence/execution-result/accepted-knowledge), supports, and proposal. Include at least one genuinely emergent uncommissioned contribution with origin=emergent and one dissenting contribution with origin=dissenting. Use non-empty critiques objects with critique_id/participant_id/target_contribution_id/concern/evidence_refs/severity/resolved; non-empty rankings with voter_id/ordered_contribution_ids/rationale; review with reviewer_id, decision exactly accepted or rejected, evidence_refs, and note (preserve dissent in contributions and unresolved_assumptions, not by inventing another decision value); and deliveries for every contribution participant with participant_id/received/returned_home/receipt_ref. Field names are exact; criteria, critique, ranking, accepted_review, delivery_receipts, and home_return_receipts are not substitutes."
    "moonrobo.digital-design.v1" =>
      "Required product contract: design_id as a lowercase slug; revision as a non-empty string such as r1; mission object with authority exactly digital-only, non-empty robot_class, and optional name; task_loop as at least four non-empty string statements; mechanisms as at least three objects with unique lowercase-slug id and non-empty kind; constraints.commanded_speed_mps.max as a positive number; and non-empty requirement_traceability entries with requirement_id, requirement, components, and verification. Encode every boolean state required for safe motion in constraints.safety_predicates as at least two objects with unique predicate_id, state_key, boolean safe_value, and a distinct adverse_scenario_id. Do not use free-form constraints.motion_requires. Each adverse_scenario_id must name a negative or degraded executable scenario whose initial_state contains state_key set to the inverse of safe_value, so every declared safety predicate is natively exercised. validation.scenarios must contain at least three executable scenarios covering kind=nominal and kind=negative or degraded. Each requires unique id, kind, expected, non-empty initial_state object, and non-empty steps. Every step requires step_id, operation, inputs, output, and expected. Inputs are objects containing either state naming an earlier state/output or literal containing a JSON value. Operations add/subtract/multiply/less_or_equal/greater_or_equal/equal/boolean_and/boolean_or take two inputs; select takes a three-element inputs array ordered condition/true-value/false-value. Use these steps to derive commanded motion, stop commands, and inhibition from scenario state so native MoonRobo can emit numerical and boolean state histories. Preserve hazards, margins, and unsupported_physical_assumptions in explicit additional fields, and remain digital only. Field shapes and singular requirement_traceability name are exact: task-loop objects, component_id mechanisms, requirements_trace, and requirements_traceability are not substitutes."
    "moonrobo.validation-evidence.v1" =>
      "Required product contract: non-empty constraint_results, negative_cases, and failure_traces. Validate the accepted digital-design input without hiding failed constraints in aggregate scores; preserve blockers and digital-only scope. Only claim a negative, degraded, or failure case as exercised when its id names an executable scenario in the accepted design; do not add unexecuted cases or describe logic inspection as execution."
    "moonmoon.scenario-evidence.v1" =>
      "Required product contract: simulation_model with global initial_energy_wh greater than reserve_energy_wh and scenarios containing both nominal and adverse kinds. Every scenario needs scenario_id, integer seed, and steps with non-negative energy_use_wh/progress_delta, hazard boolean, and recovery. The native executor starts every scenario from the global initial_energy_wh; do not add per-scenario initial_state or self-reported result fields because they are not executable inputs and are omitted from native evidence. Also include non-empty model_limitations and uncertainty."
    "moonbook.outcome-audit.v1" =>
      "Required product contract: criterion_decisions exactly matching request acceptance_criteria in original order; each decision is accepted/blocked/rejected with evidence_refs or blocker and rationale. Include non-empty open_gaps objects with the exact field kind equal to information-gap, cognition-gap, or execution-gap, plus string question and string resolution_criteria. The field type is not a substitute for kind. Also include residual_risks; a non-empty string final_claim; claim_ceiling as exactly one scalar string from observation, research-evidence, accepted-knowledge, digital-artifact, simulation-evidence, or scenario-qualified (never an object and never an explanatory sentence); and string recorded_at."
    "moonclaw.software-result.v1" =>
      "Required product contract: change_summary; implementation is an object whose language field is exactly moonsuite-helper-dsl.v1 and whose functions are objects with name, operation, and exactly two string inputs. Put operation directly on each function (not inside expression); allowed values are add/subtract/multiply/less_or_equal/greater_or_equal/equal/boolean_and/boolean_or. Include non-empty test_vectors and negative_cases with case_id/function/inputs/expected. Each test inputs value must be a JSON object keyed by the selected function's two input names, not a positional array. Set criteria_preserved true and physical_readiness false. Field names are exact: contract_id is not a substitute for implementation.language. The native MoonClaw attestor executes every vector and owns build_checks, test_results, and trial_evidence."
    _ =>
      "Follow the declared output contract and preserve all evidence boundaries."
  }
}

///|
fn request_allows_public_web(request : Json) -> Bool {
  let fields = object(request, "flow request") catch { _ => return false }
  let product_id = match fields.get("product_id") {
    Some(String(value)) => value
    _ => return false
  }
  let authority = match fields.get("requested_authority") {
    Some(String(value)) => value
    _ => return false
  }
  let evidence_contract = match fields.get("output_contracts") {
    Some(Array(values)) =>
      values.contains(Json::string("moonwiki.evidence-bundle.v1"))
    _ => false
  }
  product_id == "moonwiki" && authority == "observe" && evidence_contract
}

///|
fn draft_quality_issues(request : Json, draft : Json) -> Array[String] {
  let issues : Array[String] = []
  let request_fields = object(request, "flow request") catch {
    _ => {
      issues.push("request is not an object")
      return issues
    }
  }
  let fields = object(draft, "draft") catch {
    _ => {
      issues.push("draft is not an object")
      return issues
    }
  }
  let product = match request_fields.get("product_id") {
    Some(String(value)) => value
    _ => ""
  }
  let contract = match request_fields.get("output_contracts") {
    Some(Array([String(value), ..])) => value
    _ => ""
  }
  if fields.get("product_id") != Some(Json::string(product)) {
    issues.push("product_id must equal the request product_id")
  }
  if fields.get("contract_id") != Some(Json::string(contract)) {
    issues.push("contract_id must equal the declared output contract")
  }
  let required = match contract {
    "moonwiki.evidence-bundle.v1" =>
      [
        "sources", "claims", "contradictions", "limitations", "remaining_information_gaps",
        "query_lineage", "stopping_rationale", "web_provenance",
      ]
    "moontown.deliberation.v1" => ["civic_round"]
    "moonrobo.digital-design.v1" =>
      [
        "design_id", "revision", "mission", "task_loop", "mechanisms", "validation",
        "constraints",
      ]
    "moonrobo.validation-evidence.v1" =>
      ["constraint_results", "negative_cases", "failure_traces"]
    "moonmoon.scenario-evidence.v1" =>
      ["simulation_model", "model_limitations", "uncertainty"]
    "moonbook.outcome-audit.v1" =>
      [
        "criterion_decisions", "open_gaps", "residual_risks", "final_claim", "claim_ceiling",
        "recorded_at",
      ]
    "moonclaw.software-result.v1" =>
      ["change_summary", "implementation", "test_vectors", "negative_cases"]
    _ => []
  }
  for key in required {
    if !non_empty_field(fields, key) {
      issues.push("required field is missing or empty: \{key}")
    }
  }
  if contract == "moonwiki.evidence-bundle.v1" {
    for issue in web_provenance_issues(fields) {
      issues.push(issue)
    }
  }
  if contract == "moontown.deliberation.v1" {
    for issue in moontown_round_issues(fields) {
      issues.push(issue)
    }
  }
  if contract == "moonrobo.digital-design.v1" {
    for issue in moonrobo_design_issues(fields) {
      issues.push(issue)
    }
  }
  if contract == "moonbook.outcome-audit.v1" {
    for issue in moonbook_audit_issues(request_fields, fields) {
      issues.push(issue)
    }
  }
  if contract == "moonclaw.software-result.v1" {
    for issue in moonclaw_software_issues(fields) {
      issues.push(issue)
    }
  }
  issues
}

///|
fn moonbook_audit_issues(
  request_fields : Map[String, Json],
  fields : Map[String, Json],
) -> Array[String] {
  let issues : Array[String] = []
  let criteria = match request_fields.get("acceptance_criteria") {
    Some(Array(values)) => values
    _ => []
  }
  match fields.get("criterion_decisions") {
    Some(Array(decisions)) => {
      if decisions.length() != criteria.length() {
        issues.push("MoonBook audit must decide every criterion exactly once")
      }
      for index, value in decisions {
        guard value is Object(decision) else {
          issues.push("MoonBook criterion decision must be an object")
          continue
        }
        if index < criteria.length() &&
          decision.get("criterion") != Some(criteria[index]) {
          issues.push("MoonBook audit criteria must preserve immutable order")
        }
        match decision.get("decision") {
          Some(String(value)) if ["accepted", "blocked", "rejected"].contains(
              value,
            ) => ()
          _ =>
            issues.push(
              "MoonBook audit decision must be accepted, blocked, or rejected",
            )
        }
        let evidence_present = match decision.get("evidence_refs") {
          Some(Array(values)) => !values.is_empty()
          _ => false
        }
        let blocker_present = match decision.get("blocker") {
          Some(String(value)) => !value.trim().is_empty()
          _ => false
        }
        if !evidence_present && !blocker_present {
          issues.push(
            "MoonBook audit decisions require evidence_refs or an explicit blocker",
          )
        }
        match decision.get("evidence_refs") {
          Some(Array(values)) if values.all(value => {
              match value {
                String(text) => !text.trim().is_empty()
                _ => false
              }
            }) => ()
          _ => issues.push("MoonBook audit evidence_refs must contain strings")
        }
        match decision.get("rationale") {
          Some(String(value)) if !value.trim().is_empty() => ()
          _ =>
            issues.push(
              "MoonBook audit decisions require a non-empty rationale",
            )
        }
      }
    }
    _ => ()
  }
  match fields.get("open_gaps") {
    Some(Array(gaps)) =>
      for value in gaps {
        guard value is Object(gap) else {
          issues.push("MoonBook open gap must be an object")
          continue
        }
        match gap.get("kind") {
          Some(String(value)) if [
              "information-gap", "cognition-gap", "execution-gap",
            ].contains(value) => ()
          _ =>
            issues.push(
              "MoonBook open gaps require exact kind information-gap, cognition-gap, or execution-gap",
            )
        }
        let question_valid = match gap.get("question") {
          Some(String(value)) => !value.trim().is_empty()
          _ => false
        }
        let resolution_valid = match gap.get("resolution_criteria") {
          Some(String(value)) => !value.trim().is_empty()
          _ => false
        }
        if !question_valid || !resolution_valid {
          issues.push(
            "MoonBook open gaps require string question and resolution_criteria",
          )
        }
      }
    _ => ()
  }
  match fields.get("claim_ceiling") {
    Some(String(value)) if [
        "observation", "research-evidence", "accepted-knowledge", "digital-artifact",
        "simulation-evidence", "scenario-qualified",
      ].contains(value) => ()
    _ =>
      issues.push(
        "MoonBook claim_ceiling must be exactly one scalar string: observation, research-evidence, accepted-knowledge, digital-artifact, simulation-evidence, or scenario-qualified",
      )
  }
  match fields.get("final_claim") {
    Some(String(value)) if !value.trim().is_empty() => ()
    _ => issues.push("MoonBook final_claim must be a non-empty string")
  }
  match fields.get("recorded_at") {
    Some(String(value)) if !value.trim().is_empty() => ()
    _ => issues.push("MoonBook recorded_at must be a non-empty string")
  }
  issues
}

///|
fn has_fields(
  fields : Map[String, Json],
  names : Array[String],
) -> Array[String] {
  names.filter(name => !fields.contains(name))
}

///|
fn moonrobo_design_issues(fields : Map[String, Json]) -> Array[String] {
  let issues : Array[String] = []
  match fields.get("revision") {
    Some(String(value)) if !value.trim().is_empty() => ()
    _ =>
      issues.push("MoonRobo digital design revision must be a non-empty string")
  }
  match fields.get("mission") {
    Some(Object(mission)) => {
      if mission.get("authority") != Some(Json::string("digital-only")) {
        issues.push("MoonRobo mission.authority must equal digital-only")
      }
      if !non_empty_field(mission, "robot_class") {
        issues.push("MoonRobo mission.robot_class must be non-empty")
      }
    }
    _ => issues.push("MoonRobo mission must be an object")
  }
  match fields.get("task_loop") {
    Some(Array(steps)) if steps.length() >= 4 =>
      if steps.any(step => {
          match step {
            String(value) => value.trim().is_empty()
            _ => true
          }
        }) {
        issues.push("MoonRobo task_loop requires non-empty string statements")
      }
    _ =>
      issues.push("MoonRobo task_loop requires at least four string statements")
  }
  let mechanism_ids : Array[String] = []
  match fields.get("mechanisms") {
    Some(Array(mechanisms)) if mechanisms.length() >= 3 =>
      for mechanism in mechanisms {
        guard mechanism is Object(mechanism_fields) else {
          issues.push("MoonRobo mechanism must be an object")
          continue
        }
        let id = match mechanism_fields.get("id") {
          Some(String(value)) => value
          _ => ""
        }
        if id.trim().is_empty() || !non_empty_field(mechanism_fields, "kind") {
          issues.push("MoonRobo mechanisms require non-empty id and kind")
        } else if mechanism_ids.contains(id) {
          issues.push("MoonRobo mechanism ids must be unique")
        } else {
          mechanism_ids.push(id)
        }
      }
    _ => issues.push("MoonRobo mechanisms require at least three entries")
  }
  let scenario_ids : Array[String] = []
  let mut nominal_scenarios = 0
  let mut adverse_scenarios = 0
  match fields.get("validation") {
    Some(Object(validation)) =>
      match validation.get("scenarios") {
        Some(Array(scenarios)) if scenarios.length() >= 3 =>
          for scenario in scenarios {
            guard scenario is Object(scenario_fields) else {
              issues.push("MoonRobo validation scenario must be an object")
              continue
            }
            if !non_empty_field(scenario_fields, "id") ||
              !non_empty_field(scenario_fields, "expected") {
              issues.push(
                "MoonRobo validation scenarios require id and expected",
              )
            }
            let scenario_id = match scenario_fields.get("id") {
              Some(String(value)) => value
              _ => ""
            }
            if !scenario_id.is_empty() && scenario_ids.contains(scenario_id) {
              issues.push("MoonRobo validation scenario ids must be unique")
            } else if !scenario_id.is_empty() {
              scenario_ids.push(scenario_id)
            }
            match scenario_fields.get("kind") {
              Some(String("nominal")) => nominal_scenarios += 1
              Some(String("negative" | "degraded")) => adverse_scenarios += 1
              _ =>
                issues.push(
                  "MoonRobo validation scenario kind must be nominal, negative, or degraded",
                )
            }
            match scenario_fields.get("initial_state") {
              Some(Object(state)) if !state.is_empty() => ()
              _ =>
                issues.push(
                  "MoonRobo validation scenario initial_state must be a non-empty object",
                )
            }
            match scenario_fields.get("steps") {
              Some(Array(steps)) if !steps.is_empty() =>
                for step in steps {
                  guard step is Object(step_fields) else {
                    issues.push("MoonRobo scenario step must be an object")
                    continue
                  }
                  for key in ["step_id", "operation", "output"] {
                    if !non_empty_field(step_fields, key) {
                      issues.push("MoonRobo scenario step requires \{key}")
                    }
                  }
                  if !step_fields.contains("expected") {
                    issues.push("MoonRobo scenario step requires expected")
                  }
                  let operation = match step_fields.get("operation") {
                    Some(String(value)) => value
                    _ => ""
                  }
                  let allowed = [
                    "add", "subtract", "multiply", "less_or_equal", "greater_or_equal",
                    "equal", "boolean_and", "boolean_or", "select",
                  ]
                  if !allowed.contains(operation) {
                    issues.push("MoonRobo scenario operation is not allowed")
                  }
                  match step_fields.get("inputs") {
                    Some(Array(inputs)) => {
                      let expected_count = if operation == "select" {
                        3
                      } else {
                        2
                      }
                      if inputs.length() != expected_count {
                        issues.push(
                          "MoonRobo scenario step has the wrong input count",
                        )
                      }
                      for input in inputs {
                        guard input is Object(input_fields) else {
                          issues.push(
                            "MoonRobo scenario input must be an object",
                          )
                          continue
                        }
                        let has_state = match input_fields.get("state") {
                          Some(String(value)) => !value.trim().is_empty()
                          _ => false
                        }
                        let has_literal = input_fields.contains("literal")
                        if has_state == has_literal {
                          issues.push(
                            "MoonRobo scenario input requires exactly one of state or literal",
                          )
                        }
                      }
                    }
                    _ => issues.push("MoonRobo scenario step requires inputs")
                  }
                }
              _ =>
                issues.push(
                  "MoonRobo validation scenario steps must be non-empty",
                )
            }
          }
        _ =>
          issues.push(
            "MoonRobo validation.scenarios requires at least three entries",
          )
      }
    _ => issues.push("MoonRobo validation must be an object")
  }
  if nominal_scenarios == 0 || adverse_scenarios == 0 {
    issues.push(
      "MoonRobo validation scenarios must cover nominal and negative or degraded execution",
    )
  }
  match fields.get("constraints") {
    Some(Object(constraints)) => {
      match constraints.get("commanded_speed_mps") {
        Some(Object(speed)) =>
          match speed.get("max") {
            Some(Number(value, ..)) if value > 0.0 => ()
            _ =>
              issues.push(
                "MoonRobo constraints.commanded_speed_mps.max must be positive",
              )
          }
        _ =>
          issues.push(
            "MoonRobo constraints.commanded_speed_mps must be an object",
          )
      }
      if constraints.contains("motion_requires") {
        issues.push(
          "MoonRobo constraints must use safety_predicates instead of free-form motion_requires",
        )
      }
      let predicate_ids : Array[String] = []
      let adverse_ids : Array[String] = []
      match constraints.get("safety_predicates") {
        Some(Array(predicates)) if predicates.length() >= 2 =>
          for predicate_value in predicates {
            guard predicate_value is Object(predicate) else {
              issues.push("MoonRobo safety predicate must be an object")
              continue
            }
            let predicate_id = match predicate.get("predicate_id") {
              Some(String(value)) => value
              _ => ""
            }
            let state_key = match predicate.get("state_key") {
              Some(String(value)) => value
              _ => ""
            }
            let adverse_id = match predicate.get("adverse_scenario_id") {
              Some(String(value)) => value
              _ => ""
            }
            let safe_value = match predicate.get("safe_value") {
              Some(True) => Some(true)
              Some(False) => Some(false)
              _ => None
            }
            if predicate_id.trim().is_empty() ||
              state_key.trim().is_empty() ||
              adverse_id.trim().is_empty() ||
              safe_value is None {
              issues.push(
                "MoonRobo safety predicates require predicate_id, state_key, boolean safe_value, and adverse_scenario_id",
              )
              continue
            }
            if predicate_ids.contains(predicate_id) {
              issues.push("MoonRobo safety predicate ids must be unique")
            } else {
              predicate_ids.push(predicate_id)
            }
            if adverse_ids.contains(adverse_id) {
              issues.push(
                "MoonRobo safety predicates require distinct adverse scenarios",
              )
            } else {
              adverse_ids.push(adverse_id)
            }
            let mut covered = false
            match fields.get("validation") {
              Some(Object(validation)) =>
                match validation.get("scenarios") {
                  Some(Array(scenarios)) =>
                    for scenario_value in scenarios {
                      guard scenario_value is Object(scenario) else { continue }
                      if scenario.get("id") == Some(Json::string(adverse_id)) {
                        let adverse_kind = scenario.get("kind") ==
                          Some(Json::string("negative")) ||
                          scenario.get("kind") == Some(Json::string("degraded"))
                        let inverted = match
                          (scenario.get("initial_state"), safe_value) {
                          (Some(Object(state)), Some(value)) =>
                            state.get(state_key) == Some(Json::boolean(!value))
                          _ => false
                        }
                        if adverse_kind && inverted {
                          covered = true
                        }
                      }
                    }
                  _ => ()
                }
              _ => ()
            }
            if !covered {
              issues.push(
                "MoonRobo safety predicate must reference a distinct adverse scenario with inverted initial state",
              )
            }
          }
        _ =>
          issues.push(
            "MoonRobo constraints require at least two safety_predicates",
          )
      }
    }
    _ => issues.push("MoonRobo constraints must be an object")
  }
  match fields.get("requirement_traceability") {
    Some(Array(entries)) if !entries.is_empty() =>
      for entry in entries {
        guard entry is Object(entry_fields) else {
          issues.push(
            "MoonRobo requirement traceability entry must be an object",
          )
          continue
        }
        for
          key in ["requirement_id", "requirement", "components", "verification"] {
          if !non_empty_field(entry_fields, key) {
            issues.push("MoonRobo requirement traceability requires \{key}")
          }
        }
      }
    _ => issues.push("MoonRobo requirement_traceability must be non-empty")
  }
  issues
}

///|
fn moontown_round_issues(draft_fields : Map[String, Json]) -> Array[String] {
  let issues : Array[String] = []
  guard draft_fields.get("civic_round") is Some(Object(round)) else {
    return ["MoonTown civic_round must be an object"]
  }
  for
    missing in has_fields(round, [
      "contract_id", "round_id", "commission_id", "question", "commissioned_agenda_ids",
      "comparison_criteria", "comparison_assessments", "unresolved_assumptions",
      "contributions", "critiques", "rankings", "review", "deliveries", "requested_authority",
      "recorded_at",
    ]) {
    issues.push("MoonTown civic_round is missing field: " + missing)
  }
  if round.get("contract_id") !=
    Some(Json::string("moontown.autonomous-civic-round.v1")) {
    issues.push(
      "MoonTown civic_round contract_id must be moontown.autonomous-civic-round.v1",
    )
  }
  let criterion_ids : Array[String] = []
  match round.get("comparison_criteria") {
    Some(Array(criteria)) if !criteria.is_empty() =>
      for criterion in criteria {
        guard criterion is Object(fields) else {
          issues.push("MoonTown comparison criterion must be an object")
          continue
        }
        for
          missing in has_fields(fields, ["criterion_id", "name", "definition"]) {
          issues.push(
            "MoonTown comparison criterion is missing field: " + missing,
          )
        }
        match fields.get("criterion_id") {
          Some(String(value)) if !value.trim().is_empty() =>
            criterion_ids.push(value)
          _ => ()
        }
      }
    _ => issues.push("MoonTown civic_round requires comparison_criteria")
  }
  match round.get("unresolved_assumptions") {
    Some(Array(assumptions)) if !assumptions.is_empty() &&
      assumptions.all(assumption => {
        assumption is String(value) && !value.trim().is_empty()
      }) => ()
    _ => issues.push("MoonTown civic_round requires unresolved_assumptions")
  }
  let mut emergent = false
  let mut dissenting = false
  let contribution_ids : Array[String] = []
  match round.get("contributions") {
    Some(Array(contributions)) if contributions.length() >= 2 =>
      for contribution in contributions {
        guard contribution is Object(fields) else {
          issues.push("MoonTown contribution must be an object")
          continue
        }
        for
          missing in has_fields(fields, [
            "contribution_id", "participant_id", "source_book_id", "origin", "summary",
            "evidence_refs", "alternatives", "blockers", "implementation_criteria",
            "claim_ceiling", "supports", "proposal",
          ]) {
          issues.push("MoonTown contribution is missing field: " + missing)
        }
        match fields.get("origin") {
          Some(String("emergent")) => emergent = true
          Some(String("dissenting")) => dissenting = true
          _ => ()
        }
        match fields.get("contribution_id") {
          Some(String(value)) if !value.trim().is_empty() =>
            contribution_ids.push(value)
          _ => ()
        }
      }
    _ => issues.push("MoonTown civic_round requires at least two contributions")
  }
  if !emergent {
    issues.push("MoonTown civic_round requires an emergent contribution")
  }
  if !dissenting {
    issues.push("MoonTown civic_round requires a dissenting contribution")
  }
  match round.get("comparison_assessments") {
    Some(Array(assessments)) if !assessments.is_empty() => {
      for assessment in assessments {
        guard assessment is Object(fields) else {
          issues.push("MoonTown comparison assessment must be an object")
          continue
        }
        for
          missing in has_fields(fields, [
            "contribution_id", "criterion_id", "rating", "rationale", "evidence_refs",
          ]) {
          issues.push(
            "MoonTown comparison assessment is missing field: " + missing,
          )
        }
      }
      for contribution_id in contribution_ids {
        for criterion_id in criterion_ids {
          if !assessments.any(assessment => {
              assessment is Object(fields) &&
              fields.get("contribution_id") ==
              Some(Json::string(contribution_id)) &&
              fields.get("criterion_id") == Some(Json::string(criterion_id))
            }) {
            issues.push(
              "MoonTown comparison assessment is missing pair: " +
              contribution_id +
              "/" +
              criterion_id,
            )
          }
        }
      }
    }
    _ => issues.push("MoonTown civic_round requires comparison_assessments")
  }
  match round.get("critiques") {
    Some(Array(critiques)) if !critiques.is_empty() =>
      for critique in critiques {
        guard critique is Object(fields) else {
          issues.push("MoonTown critique must be an object")
          continue
        }
        for
          missing in has_fields(fields, [
            "critique_id", "participant_id", "target_contribution_id", "concern",
            "evidence_refs", "severity", "resolved",
          ]) {
          issues.push("MoonTown critique is missing field: " + missing)
        }
      }
    _ => issues.push("MoonTown civic_round requires critiques")
  }
  match round.get("rankings") {
    Some(Array(rankings)) if !rankings.is_empty() =>
      for ranking in rankings {
        guard ranking is Object(fields) else {
          issues.push("MoonTown ranking must be an object")
          continue
        }
        for
          missing in has_fields(fields, [
            "voter_id", "ordered_contribution_ids", "rationale",
          ]) {
          issues.push("MoonTown ranking is missing field: " + missing)
        }
      }
    _ => issues.push("MoonTown civic_round requires rankings")
  }
  match round.get("review") {
    Some(Object(fields)) => {
      for
        missing in has_fields(fields, [
          "reviewer_id", "decision", "evidence_refs", "note",
        ]) {
        issues.push("MoonTown review is missing field: " + missing)
      }
      match fields.get("decision") {
        Some(String("accepted" | "rejected")) => ()
        _ =>
          issues.push("MoonTown review decision must be accepted or rejected")
      }
    }
    _ => issues.push("MoonTown civic_round requires review")
  }
  match round.get("deliveries") {
    Some(Array(deliveries)) if !deliveries.is_empty() =>
      for delivery in deliveries {
        guard delivery is Object(fields) else {
          issues.push("MoonTown delivery must be an object")
          continue
        }
        for
          missing in has_fields(fields, [
            "participant_id", "received", "returned_home", "receipt_ref",
          ]) {
          issues.push("MoonTown delivery is missing field: " + missing)
        }
      }
    _ => issues.push("MoonTown civic_round requires deliveries")
  }
  issues
}

///|
fn moonclaw_software_issues(fields : Map[String, Json]) -> Array[String] {
  let issues : Array[String] = []
  match fields.get("criteria_preserved") {
    Some(True) => ()
    _ => issues.push("MoonClaw software result must preserve all criteria")
  }
  match fields.get("physical_readiness") {
    Some(False) => ()
    _ =>
      issues.push("MoonClaw software result must set physical_readiness false")
  }
  for key in ["implementation", "test_vectors", "negative_cases"] {
    if !non_empty_field(fields, key) {
      issues.push("MoonClaw software result requires non-empty \{key}")
    }
  }
  match fields.get("implementation") {
    Some(Object(implementation)) => {
      if implementation.get("language") !=
        Some(Json::string("moonsuite-helper-dsl.v1")) {
        issues.push(
          "MoonClaw helper implementation requires moonsuite-helper-dsl.v1",
        )
      }
      if !non_empty_field(implementation, "functions") {
        issues.push("MoonClaw helper DSL requires functions")
      } else {
        guard implementation.get("functions") is Some(Array(functions)) else {
          issues.push("MoonClaw helper DSL functions must be an array")
          return issues
        }
        for function in functions {
          guard function is Object(function_fields) else {
            issues.push("MoonClaw helper function must be an object")
            continue
          }
          if !non_empty_field(function_fields, "name") {
            issues.push("MoonClaw helper function requires name")
          }
          if !non_empty_field(function_fields, "operation") {
            issues.push(
              "MoonClaw helper function requires operation directly on the function object",
            )
          }
          match function_fields.get("inputs") {
            Some(Array([String(_), String(_)])) => ()
            _ =>
              issues.push(
                "MoonClaw helper function requires exactly two string inputs",
              )
          }
        }
      }
    }
    _ => issues.push("MoonClaw helper implementation must be an object")
  }
  for key in ["test_vectors", "negative_cases"] {
    match fields.get(key) {
      Some(Array(cases)) =>
        for test_case in cases {
          guard test_case is Object(case_fields) else {
            issues.push("MoonClaw helper test case must be an object")
            continue
          }
          match case_fields.get("inputs") {
            Some(Object(_)) => ()
            _ =>
              issues.push(
                "MoonClaw helper test inputs must be a JSON object keyed by function input names",
              )
          }
        }
      _ => ()
    }
  }
  issues
}

///|
fn dsl_string_array(
  fields : Map[String, Json],
  key : String,
) -> Array[String] raise {
  match fields.get(key) {
    Some(Array(values)) =>
      values.map(value => {
        match value {
          String(text) if !text.trim().is_empty() => text
          _ => fail("MoonClaw helper DSL requires string \{key}")
        }
      })
    _ => fail("MoonClaw helper DSL requires \{key}")
  }
}

///|
fn dsl_value(inputs : Map[String, Json], name : String) -> Json raise {
  inputs
  .get(name)
  .unwrap_or_else(() => fail("MoonClaw helper input is missing: \{name}"))
}

///|
fn dsl_number(value : Json, label : String) -> Double raise {
  match value {
    Number(number, ..) => number
    _ => fail("MoonClaw helper DSL requires numeric \{label}")
  }
}

///|
fn evaluate_helper_function(
  function : Map[String, Json],
  inputs : Map[String, Json],
) -> Json raise {
  let operation = string_field(function, "operation")
  let names = dsl_string_array(function, "inputs")
  if names.length() != 2 {
    fail("MoonClaw helper DSL operations require exactly two inputs")
  }
  let left = dsl_value(inputs, names[0])
  let right = dsl_value(inputs, names[1])
  match operation {
    "add" =>
      Json::number(dsl_number(left, names[0]) + dsl_number(right, names[1]))
    "subtract" =>
      Json::number(dsl_number(left, names[0]) - dsl_number(right, names[1]))
    "multiply" =>
      Json::number(dsl_number(left, names[0]) * dsl_number(right, names[1]))
    "less_or_equal" =>
      Json::boolean(dsl_number(left, names[0]) <= dsl_number(right, names[1]))
    "greater_or_equal" =>
      Json::boolean(dsl_number(left, names[0]) >= dsl_number(right, names[1]))
    "equal" => Json::boolean(left == right)
    "boolean_and" =>
      match (left, right) {
        (True, True) => Json::boolean(true)
        (True | False, True | False) => Json::boolean(false)
        _ => fail("MoonClaw helper boolean_and requires booleans")
      }
    "boolean_or" =>
      match (left, right) {
        (False, False) => Json::boolean(false)
        (True | False, True | False) => Json::boolean(true)
        _ => fail("MoonClaw helper boolean_or requires booleans")
      }
    _ => fail("MoonClaw helper DSL operation is not allowed: \{operation}")
  }
}

///|
fn validate_helper_software_with_criteria(
  fields : Map[String, Json],
  acceptance_criteria : Json,
) -> Json raise {
  let implementation = object(
    fields.get("implementation").unwrap_or(Json::null()),
    "helper implementation",
  )
  if string_field(implementation, "language") != "moonsuite-helper-dsl.v1" {
    fail("MoonClaw helper DSL language is unsupported")
  }
  let functions = match implementation.get("functions") {
    Some(Array(values)) if !values.is_empty() => values
    _ => fail("MoonClaw helper DSL requires functions")
  }
  let function_names : Array[String] = []
  for value in functions {
    let function = object(value, "helper function")
    let name = string_field(function, "name")
    if function_names.contains(name) {
      fail("MoonClaw helper function names must be unique")
    }
    function_names.push(name)
    ignore(string_field(function, "operation"))
    if dsl_string_array(function, "inputs").length() != 2 {
      fail("MoonClaw helper DSL operations require exactly two inputs")
    }
  }
  let results : Array[Json] = []
  let execution_transcript : Array[Json] = []
  for pair in [("positive", "test_vectors"), ("negative", "negative_cases")] {
    let (class, key) = pair
    guard fields.get(key) is Some(Array(cases)) && !cases.is_empty() else {
      fail("MoonClaw helper DSL requires \{key}")
    }
    for value in cases {
      let test_case = object(value, "helper test case")
      let function_name = string_field(test_case, "function")
      let mut selected : Map[String, Json]? = None
      for candidate in functions {
        let candidate_fields = object(candidate, "helper function")
        if string_field(candidate_fields, "name") == function_name {
          selected = Some(candidate_fields)
        }
      }
      guard selected is Some(function) else {
        fail(
          "MoonClaw helper test references unknown function: \{function_name}",
        )
      }
      let inputs = object(
        test_case.get("inputs").unwrap_or(Json::null()),
        "helper test inputs",
      )
      let expected = test_case.get("expected").unwrap_or(Json::null())
      let actual = evaluate_helper_function(function, inputs)
      if actual != expected {
        fail(
          "MoonClaw helper test failed: \{string_field(test_case, "case_id")}",
        )
      }
      results.push({
        "case_id": string_field(test_case, "case_id"),
        "class": class,
        "function": function_name,
        "inputs": Json::object(inputs),
        "expected": expected,
        "actual": actual,
        "passed": true,
        "execution_owner": "native MoonClaw wrapper",
      })
      execution_transcript.push({
        "sequence": execution_transcript.length(),
        "case_id": string_field(test_case, "case_id"),
        "class": class,
        "function": function_name,
        "operation": string_field(function, "operation"),
        "input_bindings": Json::object(inputs),
        "expected": expected,
        "actual": actual,
        "comparison": "exact-json-equality",
        "executed_by": "native MoonClaw wrapper",
        "status": "passed",
      })
    }
  }
  let criterion_preservation : Array[Json] = []
  match acceptance_criteria {
    Array(criteria) =>
      for criterion in criteria {
        guard criterion is String(text) && !text.trim().is_empty() else {
          continue
        }
        criterion_preservation.push({
          "criterion": text,
          "preserved": true,
          "verified_by": "native MoonClaw wrapper",
          "evidence_sections": [
            "build_checks", "test_results", "implementation", "physical_readiness",
          ],
        })
      }
    _ => ()
  }
  {
    "contract_id": "moonclaw.software-result.v1",
    "product_id": "moonclaw",
    "change_summary": string_field(fields, "change_summary"),
    "implementation": Json::object(implementation),
    "build_checks": [
      {
        "check": "bounded-helper-dsl-schema-and-type-check",
        "status": "passed",
        "validator": "moonclaw-native-attestor",
        "owner": "native MoonClaw wrapper",
        "wrapper_owned": true,
      },
    ],
    "test_results": results.to_json(),
    "execution_transcript": execution_transcript.to_json(),
    "test_vectors": fields.get("test_vectors").unwrap_or(Json::array([])),
    "negative_cases": fields.get("negative_cases").unwrap_or(Json::array([])),
    "trial_evidence": [
      {
        "trial": "native-helper-dsl-validation",
        "result": "accepted",
        "case_count": results.length(),
        "execution_owner": "native MoonClaw wrapper",
        "evidence_kind": "executed-vector-transcript",
      },
    ],
    "criterion_preservation": criterion_preservation.to_json(),
    "criteria_preserved": true,
    "physical_readiness": false,
  }
}

///|
fn hex_digit(value : Int) -> Char {
  if value < 10 {
    ('0'.to_int() + value).unsafe_to_char()
  } else {
    ('a'.to_int() + value - 10).unsafe_to_char()
  }
}

///|
fn sha256_hex(bytes : Bytes) -> String {
  let digest = @crypto.sha256(bytes)
  let builder = StringBuilder::new()
  for byte in digest {
    let value = byte.to_int()
    builder.write_char(hex_digit(value / 16))
    builder.write_char(hex_digit(value % 16))
  }
  builder.to_string()
}

///|
async fn artifact_digest(
  workspace : String,
  artifacts : Array[String],
) -> String {
  let identities : Array[String] = []
  for artifact in artifacts {
    let data = @fs.read_file(
      workspace + "/" + require_ref(artifact, "artifact"),
    )
    identities.push("\{artifact}|sha256:\{sha256_hex(data.binary())}")
  }
  "sha256:" + sha256_hex(@utf8.encode(identities.join("\n")))
}

///|
async fn execute_agent(
  task_root : String,
  model_name : String,
  prompt : String,
  log_path : String,
  web_search : Bool,
) -> Array[Json] {
  let model = @model.load(name=model_name)
  guard model is Some(model) else {
    fail("MoonClaw flow adapter model is unavailable: \{model_name}")
  }
  let logger = @pino.logger(
    "moonclaw_flow_adapter",
    try! @pino.Transport::parse("file:\{log_path}"),
  )
  let worker = @moonclaw.Moonclaw::new(
    name="moonflow-worker",
    logger~,
    model~,
    cwd=task_root,
    user_message=prompt,
    web_search~,
    restricted_workspace=true,
  )
  defer worker.close()
  let web_provenance : Array[Json] = []
  worker.agent.add_listener(event => {
    match event.desc {
      PostToolCall(tool_call, result~, ..) if tool_call.name == "web_search" ||
        tool_call.name == "web_fetch" => {
        let arguments = match tool_call.arguments {
          Some(value) => @json.parse(value) catch { _ => Json::string(value) }
          None => Json::object({})
        }
        web_provenance.push({
          "tool": tool_call.name,
          "arguments": arguments,
          "succeeded": result is Ok(_),
          "event_digest": "sha256:" +
          sha256_hex(@utf8.encode(event.desc.to_json().stringify())),
        })
      }
      _ => ()
    }
  })
  worker.start()
  web_provenance
}

///|
fn execution_prompt(
  request : Json,
  artifacts : Array[String],
  trial : Int,
  feedback : Array[String],
) -> String {
  "You are a bounded MoonFlow product adapter executing one declared digital work item inside an isolated task capsule. You cannot access the parent suite workspace.\n" +
  "The immutable request follows:\n```json\n" +
  request.stringify(indent=2) +
  "\n```\n" +
  "Write exactly these declared output artifacts, relative to the workspace: " +
  artifacts.join(", ") +
  ". Each artifact must be a JSON object whose contract_id is one of the request's output_contracts and whose product_id equals the request product_id.\n" +
  contract_guidance(request) +
  "\nRead every declared input artifact before acting. Preserve sources, uncertainty, contradictions, negative cases, and trial evidence appropriate to the product and operation. Do not weaken or rewrite acceptance criteria. Do not claim physical construction, deployment, or readiness. Do not write the MoonFlow result receipt; the adapter wrapper owns it. This is bounded trial " +
  "\{trial}. If prior partial artifacts exist, diagnose and improve them rather than hiding the failure." +
  (if trial > 1 {
    " Previous rejected drafts are read-only at: " +
    artifacts.map(artifact => artifact + ".prior").join(", ") +
    ". Write one complete replacement JSON object at each declared output path; do not append to the .prior files."
  } else {
    ""
  }) +
  (if feedback.is_empty() {
    ""
  } else {
    "\nThe previous draft was rejected locally for these contract issues; revise it in place:\n- " +
    feedback.join("\n- ")
  })
}

///|
async fn attest(args : Array[String]) -> Unit {
  let workspace = required_option(args, "--workspace")
  let request_ref = require_ref(required_option(args, "--request"), "request")
  let result_ref = require_ref(required_option(args, "--result"), "result")
  let attestation_ref = require_ref(
    required_option(args, "--attestation"),
    "attestation",
  )
  let attestor_id = required_option(args, "--attestor-id")
  let draft_ref = require_ref(required_option(args, "--draft"), "draft")
  let final_ref = require_ref(
    required_option(args, "--final"),
    "product-owned final artifact",
  )
  let request = read_json(workspace + "/" + request_ref)
  let request_fields = object(request, "flow request")
  let result = read_json(workspace + "/" + result_ref)
  let result_fields = object(result, "flow result")
  let product_id = string_field(request_fields, "product_id")
  if string_field(result_fields, "product_id") != product_id {
    fail("MoonClaw product attestor rejected a product identity mismatch")
  }
  let output_contracts = match request_fields.get("output_contracts") {
    Some(Array(values)) =>
      values.filter_map(value => {
        match value {
          String(contract) => Some(contract)
          _ => None
        }
      })
    _ => []
  }
  let artifacts = match result_fields.get("output_artifacts") {
    Some(Array(values)) =>
      values.map(value => {
        match value {
          String(reference) => require_ref(reference, "attested artifact")
          _ => fail("MoonClaw product attestor requires string artifact refs")
        }
      })
    _ => fail("MoonClaw product attestor requires output_artifacts")
  }
  if artifacts.is_empty() || output_contracts.is_empty() {
    fail("MoonClaw product attestor requires declared artifacts and contracts")
  }
  if artifacts != [draft_ref] || draft_ref == final_ref {
    fail(
      "MoonClaw product attestor requires one distinct declared draft and final artifact",
    )
  }
  let observed_contracts : Array[String] = []
  for artifact in artifacts {
    let value = read_json(workspace + "/" + artifact)
    let fields = object(value, "attested product artifact")
    let contract_id = string_field(fields, "contract_id")
    if !output_contracts.contains(contract_id) {
      fail(
        "MoonClaw product attestor rejected undeclared contract \{contract_id}",
      )
    }
    match fields.get("product_id") {
      Some(String(actual)) if actual == product_id => ()
      _ => fail("MoonClaw product attestor rejected artifact product identity")
    }
    observed_contracts.push(contract_id)
  }
  for contract in output_contracts {
    if !observed_contracts.contains(contract) {
      fail(
        "MoonClaw product attestor did not observe required contract \{contract}",
      )
    }
  }
  let draft_value = read_json(workspace + "/" + draft_ref)
  let mut product_final = draft_value
  if product_id == "moonclaw" &&
    output_contracts.contains("moonclaw.software-result.v1") {
    let software_fields = object(draft_value, "MoonClaw software result")
    let software_issues = moonclaw_software_issues(software_fields)
    if !software_issues.is_empty() {
      fail(
        "MoonClaw rejected its software result: \{software_issues.join("; ")}",
      )
    }
    product_final = validate_helper_software_with_criteria(
      software_fields,
      request_fields.get("acceptance_criteria").unwrap_or(Json::array([])),
    )
  }
  // The contract attestor is the product boundary that materializes the final
  // artifact. MoonFlow reconciles this path, never the agent-authored draft.
  write_json(workspace + "/" + final_ref, product_final)
  write_json(workspace + "/" + attestation_ref, {
    "contract_id": "moonflow.product-attestation.v1",
    "attestor_id": attestor_id,
    "product_id": product_id,
    "request_id": string_field(request_fields, "request_id"),
    "result_id": string_field(result_fields, "result_id"),
    "output_digest": string_field(result_fields, "output_digest"),
    "accepted": true,
    "observed_contracts": observed_contracts.to_json(),
    "artifact_refs": artifacts.to_json(),
    "final_artifact_ref": final_ref,
  })
}

///|
async fn execute(args : Array[String]) -> Unit {
  let workspace = required_option(args, "--workspace")
  let request_ref = require_ref(required_option(args, "--request"), "request")
  let result_ref = require_ref(required_option(args, "--result"), "result")
  let model_name = required_option(args, "--model")
  let artifacts = repeated_option(args, "--artifact")
  if artifacts.is_empty() {
    fail("MoonClaw flow adapter requires at least one --artifact")
  }
  for artifact in artifacts {
    ignore(require_ref(artifact, "output artifact"))
  }
  let max_trials = match option(args, "--max-trials") {
    Some(value) => @string.parse_int(value)
    None => 3
  }
  if max_trials < 1 || max_trials > 10 {
    fail("MoonClaw flow adapter max trials must be between 1 and 10")
  }
  let request = read_json(workspace + "/" + request_ref)
  let fields = object(request, "flow request")
  let input_artifacts = match fields.get("input_artifacts") {
    Some(Array(values)) =>
      values.map(value => {
        match value {
          String(reference) => require_ref(reference, "input artifact")
          _ => fail("MoonClaw flow adapter requires string input artifact refs")
        }
      })
    _ => []
  }
  let attempt_id = string_field(fields, "attempt_id")
  let run_root = flow_attempt_root(
    workspace,
    string_field(fields, "run_id"),
    attempt_id,
  )
  @fsx.make_directory(run_root, recursive=true, exists_ok=true)
  let mut completed = false
  let mut trials = 0
  let mut feedback : Array[String] = []
  while trials < max_trials && !completed {
    trials += 1
    let capsule_root = run_root + "/capsules/trial-\{trials}"
    @fsx.make_directory(capsule_root, recursive=true, exists_ok=true)
    write_json(capsule_root + "/request.json", request)
    for artifact in input_artifacts {
      let source = workspace + "/" + artifact
      if !@fsx.exists(source) {
        fail("MoonClaw flow adapter input artifact is missing: \{artifact}")
      }
      let destination = capsule_root + "/" + artifact
      @fsx.make_directory(
        @pathx.dirname(destination),
        recursive=true,
        exists_ok=true,
      )
      @fsx.write_to_file(destination, @fsx.read_file(source), create=0o444)
    }
    for artifact in artifacts {
      let prior = workspace + "/" + artifact
      if trials > 1 && @fsx.exists(prior) {
        // The restricted writer appends to existing files. Preserve rejected
        // evidence at a distinct read-only path so the declared output starts
        // absent and the corrective trial can write a complete replacement.
        let destination = capsule_root + "/" + artifact + ".prior"
        @fsx.make_directory(
          @pathx.dirname(destination),
          recursive=true,
          exists_ok=true,
        )
        @fsx.write_to_file(destination, @fsx.read_file(prior), create=0o444)
      }
    }
    let web_provenance = execute_agent(
      capsule_root,
      model_name,
      execution_prompt(request, artifacts, trials, feedback),
      run_root + "/trial-\{trials}.jsonl",
      request_allows_public_web(request),
    ) catch {
      _ => []
    }
    completed = true
    for artifact in artifacts {
      let capsule_output = capsule_root + "/" + artifact
      if !@fsx.exists(capsule_output) {
        completed = false
        feedback = ["declared output artifact is missing: \{artifact}"]
      } else {
        let draft = read_json(capsule_output) catch {
          _ => {
            completed = false
            feedback = [
              "declared output artifact is not valid JSON: \{artifact}",
            ]
            Json::null()
          }
        }
        if completed && request_allows_public_web(request) {
          guard draft is Object(draft_fields) else {
            completed = false
            feedback = ["MoonWiki evidence draft must be an object"]
            continue
          }
          draft_fields["web_provenance"] = web_provenance.to_json()
          write_json(capsule_output, draft)
        }
        let issues = draft_quality_issues(request, draft)
        if !issues.is_empty() {
          completed = false
          feedback = issues
        }
        let workspace_output = workspace + "/" + artifact
        @fsx.make_directory(
          @pathx.dirname(workspace_output),
          recursive=true,
          exists_ok=true,
        )
        @fsx.write_to_file(
          workspace_output,
          @fsx.read_file(capsule_output),
          create=0o644,
        )
      }
    }
  }
  let output_digest = if completed {
    artifact_digest(workspace, artifacts)
  } else {
    ""
  }
  write_json(workspace + "/" + result_ref, {
    "result_id": "result-" +
    attempt_id +
    (if completed { "-succeeded" } else { "-failed" }),
    "request_id": string_field(fields, "request_id"),
    "attempt_id": attempt_id,
    "idempotency_key": string_field(fields, "idempotency_key"),
    "product_id": string_field(fields, "product_id"),
    "external_job_id": "moonclaw-" + attempt_id,
    "status": if completed {
      "succeeded"
    } else {
      "failed"
    },
    "output_digest": output_digest,
    "output_artifacts": if completed {
      artifacts.to_json()
    } else {
      Json::array([])
    },
    "error_kind": if completed {
      ""
    } else {
      "declared-artifacts-missing"
    },
    "compensable": true,
    "recorded_at": string_field(fields, "created_at"),
    "trial_count": trials,
  })
  if !completed {
    fail("MoonClaw flow adapter exhausted trials without declared artifacts")
  }
}

///|
fn review_prompt(
  packet : Json,
  trial : Int,
  feedback : Array[String],
) -> String {
  "You are an independent MoonFlow acceptance reviewer in an isolated task capsule. You did not execute this work and cannot access the parent suite workspace.\n" +
  "Review the immutable request below and inspect the exact evidence files it names. Decide every criterion in the original order. A satisfied criterion requires evidence_refs copied exactly from the request's evidence_refs array; JSON pointers or undeclared paths are prohibited. Never accept an agent or executor summary alone. A verified product attestation plus product-native per-case execution_transcript, scenario_execution, or scenario_results with resolved inputs, actual outputs, hazard/recovery scripts, and state history is direct product evidence, not a summary assertion. Reject missing negative cases, unsupported claims, and any physical-readiness overclaim. Preserve limitations and dissent. You may not grant authority or change criteria.\n" +
  "The product attestation has already been checked by MoonFlow against executor_output_digest. The request output_digest separately binds MoonFlow's immutable evidence snapshots. Follow digest_lineage: these stage digests are not expected to be equal because their artifact identities differ.\n" +
  "Write exactly one JSON object at receipt_artifact with only this contract shape: contract_id=moonflow.acceptance-review.v1; review_id, run_id, work_item_id, declaration_id, result_id, attempt_id, output_digest, reviewer_id, review_authority_id, receipt_artifact, and recorded_at copied exactly from the request; decision equal to accepted or rejected; criteria an array in the exact request order with objects containing criterion, satisfied, evidence_refs, and non-empty note. An accepted decision requires every criterion satisfied. A rejected decision requires at least one unsatisfied criterion. Do not use accepted, rationale, limitations, or JSON-pointer evidence fields as substitutes. This is bounded review trial " +
  "\{trial}." +
  (if feedback.is_empty() {
    ""
  } else {
    "\nThe previous receipt was rejected locally for these contract issues; correct them without weakening the criteria:\n- " +
    feedback.join("\n- ")
  }) +
  "\n```json\n" +
  packet.stringify(indent=2) +
  "\n```"
}

///|
fn review_receipt_issues(packet : Json, receipt : Json) -> Array[String] {
  let issues : Array[String] = []
  let packet_fields = object(packet, "review packet") catch {
    _ => return ["review packet must be an object"]
  }
  let receipt_fields = object(receipt, "review receipt") catch {
    _ => return ["review receipt must be an object"]
  }
  if receipt_fields.get("contract_id") !=
    Some(Json::string("moonflow.acceptance-review.v1")) {
    issues.push("contract_id must be moonflow.acceptance-review.v1")
  }
  for
    key in [
      "review_id", "run_id", "work_item_id", "declaration_id", "result_id", "attempt_id",
      "output_digest", "reviewer_id", "review_authority_id", "receipt_artifact",
      "recorded_at",
    ] {
    match (packet_fields.get(key), receipt_fields.get(key)) {
      (Some(String(expected)), Some(String(actual))) if expected == actual => ()
      _ =>
        issues.push("receipt identity must exactly copy request field: " + key)
    }
  }
  let decision = match receipt_fields.get("decision") {
    Some(String(value)) if value == "accepted" || value == "rejected" => value
    _ => {
      issues.push("decision must be accepted or rejected")
      ""
    }
  }
  let allowed_evidence = match packet_fields.get("evidence_refs") {
    Some(Array(values)) => values
    _ => {
      issues.push("review request evidence_refs are missing")
      []
    }
  }
  let expected_criteria = match packet_fields.get("acceptance_criteria") {
    Some(Array(values)) => values
    _ => {
      issues.push("review request acceptance_criteria are missing")
      []
    }
  }
  let criteria = match receipt_fields.get("criteria") {
    Some(Array(values)) => values
    _ => {
      issues.push("criteria must be an array")
      []
    }
  }
  if criteria.length() != expected_criteria.length() {
    issues.push("criteria must match request count and order")
  }
  let mut all_satisfied = !criteria.is_empty()
  for index in 0..<criteria.length().min(expected_criteria.length()) {
    guard criteria[index] is Object(review) else {
      issues.push("criterion review must be an object")
      all_satisfied = false
      continue
    }
    if review.get("criterion") != Some(expected_criteria[index]) {
      issues.push("criterion text and order must exactly match the request")
    }
    let satisfied = review.get("satisfied") == Some(Json::boolean(true))
    if review.get("satisfied") != Some(Json::boolean(true)) &&
      review.get("satisfied") != Some(Json::boolean(false)) {
      issues.push("criterion satisfied must be a boolean")
    }
    if !satisfied {
      all_satisfied = false
    }
    match review.get("evidence_refs") {
      Some(Array(refs)) => {
        if satisfied && refs.is_empty() {
          issues.push("satisfied criterion requires evidence_refs")
        }
        for reference in refs {
          if !allowed_evidence.contains(reference) {
            issues.push(
              "criterion evidence_ref must exactly match a request evidence_ref",
            )
          }
        }
      }
      _ => issues.push("criterion evidence_refs must be an array")
    }
    match review.get("note") {
      Some(String(value)) if !value.trim().is_empty() => ()
      _ => issues.push("criterion note is required")
    }
  }
  if decision == "accepted" && !all_satisfied {
    issues.push("accepted decision requires every criterion satisfied")
  }
  if decision == "rejected" && all_satisfied {
    issues.push("rejected decision requires an unsatisfied criterion")
  }
  issues
}

///|
async fn review(args : Array[String]) -> Unit {
  let workspace = required_option(args, "--workspace")
  let packet_ref = require_ref(
    required_option(args, "--review-packet"),
    "review packet",
  )
  let model_name = required_option(args, "--model")
  let packet = read_json(workspace + "/" + packet_ref)
  let fields = object(packet, "review packet")
  let receipt_ref = require_ref(
    string_field(fields, "receipt_artifact"),
    "receipt artifact",
  )
  let attempt_id = string_field(fields, "attempt_id")
  let log_root = workspace +
    "/.moonsuite/products/moonclaw/reviews/" +
    require_segment(string_field(fields, "run_id"), "run_id") +
    "/" +
    require_segment(attempt_id, "attempt_id")
  @fsx.make_directory(log_root, recursive=true, exists_ok=true)
  let review_inputs : Array[String] = []
  match fields.get("evidence_refs") {
    Some(Array(values)) =>
      for value in values {
        match value {
          String(reference) =>
            review_inputs.push(require_ref(reference, "review evidence"))
          _ => fail("MoonClaw reviewer requires string evidence refs")
        }
      }
    _ => fail("MoonClaw reviewer requires evidence_refs")
  }
  match fields.get("product_attestation_ref") {
    Some(String(reference)) =>
      review_inputs.push(require_ref(reference, "product attestation"))
    _ => fail("MoonClaw reviewer requires product attestation evidence")
  }
  let mut capsule_receipt = ""
  let mut feedback : Array[String] = []
  for trial in 1..<=3 {
    let capsule_root = log_root + "/capsules/trial-\{trial}"
    @fsx.make_directory(capsule_root, recursive=true, exists_ok=true)
    for artifact in review_inputs {
      let source = workspace + "/" + artifact
      if !@fsx.exists(source) {
        fail("MoonClaw reviewer evidence is missing: \{artifact}")
      }
      let destination = capsule_root + "/" + artifact
      @fsx.make_directory(
        @pathx.dirname(destination),
        recursive=true,
        exists_ok=true,
      )
      @fsx.write_to_file(destination, @fsx.read_file(source), create=0o444)
    }
    write_json(capsule_root + "/review-packet.json", packet)
    ignore(
      execute_agent(
        capsule_root,
        model_name,
        review_prompt(packet, trial, feedback),
        log_root + "/trial-\{trial}.jsonl",
        false,
      ),
    )
    let candidate = capsule_root + "/" + receipt_ref
    if !@fsx.exists(candidate) {
      feedback = ["declared review receipt is missing"]
      continue
    }
    let candidate_value = read_json(candidate) catch {
      _ => {
        feedback = ["declared review receipt is not valid JSON"]
        continue
      }
    }
    let issues = review_receipt_issues(packet, candidate_value)
    if issues.is_empty() {
      capsule_receipt = candidate
      break
    }
    feedback = issues
  }
  if capsule_receipt.is_empty() {
    fail(
      "MoonClaw independent reviewer exhausted bounded trials: " +
      feedback.join("; "),
    )
  }
  let workspace_receipt = workspace + "/" + receipt_ref
  @fsx.make_directory(
    @pathx.dirname(workspace_receipt),
    recursive=true,
    exists_ok=true,
  )
  @fsx.write_to_file(
    workspace_receipt,
    @fsx.read_file(capsule_receipt),
    create=0o644,
  )
}

///|
pub async fn run(args : ArrayView[String]) -> Unit {
  let owned = args.to_owned()
  match owned {
    ["execute", .. rest] => execute(rest.to_owned())
    ["attest", .. rest] => attest(rest.to_owned())
    ["review", .. rest] => review(rest.to_owned())
    _ =>
      println(
        "moonclaw flow-adapter usage:\n  moonclaw flow-adapter execute --workspace <root> --request <ref> --result <ref> --model <id> --artifact <ref>... [--max-trials <n>]\n  moonclaw flow-adapter attest --workspace <root> --request <ref> --result <ref> --attestation <ref> --attestor-id <id>\n  moonclaw flow-adapter review --workspace <root> --review-packet <ref> --model <id>",
      )
  }
}
