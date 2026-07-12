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
      "Required product contract: civic_round is exactly a moontown.autonomous-civic-round.v1 object with round_id, commission_id, question, commissioned_agenda_ids, requested_authority, and recorded_at. Include non-empty comparison_criteria objects with criterion_id, name, and definition so rankings remain independently interpretable, plus non-empty unresolved_assumptions strings preserved by the recommendation. It needs at least two contributions; every contribution requires contribution_id, participant_id, source_book_id, origin (commissioned/emergent/dissenting/minority/synthesized), summary, evidence_refs, alternatives, blockers, implementation_criteria, claim_ceiling (observation/research-evidence/execution-result/accepted-knowledge), supports, and proposal. Include at least one genuinely emergent uncommissioned contribution with origin=emergent and one dissenting contribution with origin=dissenting. Use non-empty critiques objects with critique_id/participant_id/target_contribution_id/concern/evidence_refs/severity/resolved; non-empty rankings with voter_id/ordered_contribution_ids/rationale; review with reviewer_id, decision exactly accepted or rejected, evidence_refs, and note (preserve dissent in contributions and unresolved_assumptions, not by inventing another decision value); and deliveries for every contribution participant with participant_id/received/returned_home/receipt_ref. Field names are exact; criteria, critique, ranking, accepted_review, delivery_receipts, and home_return_receipts are not substitutes."
    "moonrobo.digital-design.v1" =>
      "Required product contract: design_id, integer revision, mission, task_loop, mechanisms, validation, and constraints. The design must be generic to the selected concept, trace requirements to components, preserve hazards/margins/unsupported assumptions, and remain digital only."
    "moonrobo.validation-evidence.v1" =>
      "Required product contract: non-empty constraint_results, negative_cases, and failure_traces. Validate the accepted digital-design input without hiding failed constraints in aggregate scores; preserve blockers and digital-only scope."
    "moonmoon.scenario-evidence.v1" =>
      "Required product contract: simulation_model with initial_energy_wh greater than reserve_energy_wh and scenarios containing both nominal and adverse kinds. Every scenario needs scenario_id, integer seed, and steps with non-negative energy_use_wh/progress_delta, hazard boolean, and recovery. Also include non-empty model_limitations and uncertainty."
    "moonbook.outcome-audit.v1" =>
      "Required product contract: criterion_decisions exactly matching request acceptance_criteria in original order; each decision is accepted/blocked/rejected with evidence_refs or blocker and rationale. Include non-empty open_gaps using information-gap/cognition-gap/execution-gap with question and resolution_criteria, residual_risks, final_claim, bounded claim_ceiling, and recorded_at."
    "moonclaw.software-result.v1" =>
      "Required product contract: change_summary; implementation using moonsuite-helper-dsl.v1 with named two-input functions and only add/subtract/multiply/less_or_equal/greater_or_equal/equal/boolean_and/boolean_or operations; non-empty test_vectors and negative_cases with case_id/function/inputs/expected; criteria_preserved true; physical_readiness false. The native MoonClaw attestor executes every vector and owns build_checks, test_results, and trial_evidence."
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
fn moontown_round_issues(draft_fields : Map[String, Json]) -> Array[String] {
  let issues : Array[String] = []
  guard draft_fields.get("civic_round") is Some(Object(round)) else {
    return ["MoonTown civic_round must be an object"]
  }
  for
    missing in has_fields(round, [
      "contract_id", "round_id", "commission_id", "question", "commissioned_agenda_ids",
      "comparison_criteria", "unresolved_assumptions", "contributions", "critiques",
      "rankings", "review", "deliveries", "requested_authority", "recorded_at",
    ]) {
    issues.push("MoonTown civic_round is missing field: " + missing)
  }
  if round.get("contract_id") !=
    Some(Json::string("moontown.autonomous-civic-round.v1")) {
    issues.push(
      "MoonTown civic_round contract_id must be moontown.autonomous-civic-round.v1",
    )
  }
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
      }
    _ => issues.push("MoonTown civic_round requires at least two contributions")
  }
  if !emergent {
    issues.push("MoonTown civic_round requires an emergent contribution")
  }
  if !dissenting {
    issues.push("MoonTown civic_round requires a dissenting contribution")
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
      }
    }
    _ => issues.push("MoonClaw helper implementation must be an object")
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
fn validate_helper_software(fields : Map[String, Json]) -> Json raise {
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
        "expected": expected,
        "actual": actual,
        "passed": true,
      })
    }
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
      },
    ],
    "test_results": results.to_json(),
    "negative_cases": fields.get("negative_cases").unwrap_or(Json::array([])),
    "trial_evidence": [
      {
        "trial": "native-helper-dsl-validation",
        "result": "accepted",
        "case_count": results.length(),
      },
    ],
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
    product_final = validate_helper_software(software_fields)
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
  "Review the immutable request below and inspect the exact evidence files it names. Decide every criterion in the original order. A satisfied criterion requires evidence_refs copied exactly from the request's evidence_refs array; JSON pointers or undeclared paths are prohibited. Never accept an executor summary alone. Reject missing negative cases, unsupported claims, and any physical-readiness overclaim. Preserve limitations and dissent. You may not grant authority or change criteria.\n" +
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
