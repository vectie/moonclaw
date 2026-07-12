///|
test "flow adapter parses repeated options and rejects path escape" {
  let args = [
    "--model", "codex/test", "--artifact", "books/a.json", "--artifact", "books/b.json",
  ]
  assert_true(option(args, "--model") == Some("codex/test"))
  assert_true(
    repeated_option(args, "--artifact") == ["books/a.json", "books/b.json"],
  )
  assert_true(safe_ref("books/a.json"))
  assert_false(safe_ref("../escape"))
  assert_false(safe_ref("/absolute"))
}

///|
test "flow capsules are isolated by run and attempt identity" {
  let first = flow_attempt_root(
    "/suite", "flow-robot-r2", "attempt-work-research-1",
  )
  let second = flow_attempt_root(
    "/suite", "flow-robot-r3", "attempt-work-research-1",
  )
  assert_true(first != second)
  assert_true(first.contains("/flow/flow-robot-r2/attempt-work-research-1"))
  let escaped = try {
    ignore(flow_attempt_root("/suite", "../escape", "attempt-1"))
    false
  } catch {
    _ => true
  }
  assert_true(escaped)
}

///|
test "independent review prompt and validator preserve canonical receipt contract" {
  let packet : Json = {
    "review_id": "review-attempt-1",
    "run_id": "flow-run-r1",
    "work_item_id": "work-research",
    "declaration_id": "research",
    "result_id": "result-attempt-1-succeeded",
    "attempt_id": "attempt-1",
    "output_digest": "sha256:final-evidence",
    "executor_output_digest": "sha256:draft",
    "acceptance_criteria": ["evidence is traceable"],
    "evidence_refs": ["evidence/research.artifact"],
    "reviewer_id": "independent-reviewer",
    "review_authority_id": "review-policy-v1",
    "receipt_artifact": "reviews/receipt.json",
    "recorded_at": "2026-07-12T00:00:00Z",
  }
  let prompt = review_prompt(packet, 1, [])
  assert_true(prompt.contains("criteria an array in the exact request order"))
  assert_true(prompt.contains("stage digests are not expected to be equal"))
  assert_true(prompt.contains("scenario_results with resolved inputs"))
  assert_true(prompt.contains("hazard/recovery scripts"))
  let accepted : Json = {
    "contract_id": "moonflow.acceptance-review.v1",
    "review_id": "review-attempt-1",
    "run_id": "flow-run-r1",
    "work_item_id": "work-research",
    "declaration_id": "research",
    "result_id": "result-attempt-1-succeeded",
    "attempt_id": "attempt-1",
    "output_digest": "sha256:final-evidence",
    "decision": "accepted",
    "criteria": [
      {
        "criterion": "evidence is traceable",
        "satisfied": true,
        "evidence_refs": ["evidence/research.artifact"],
        "note": "The immutable evidence contains traceable sources.",
      },
    ],
    "reviewer_id": "independent-reviewer",
    "review_authority_id": "review-policy-v1",
    "receipt_artifact": "reviews/receipt.json",
    "recorded_at": "2026-07-12T00:00:00Z",
  }
  assert_true(review_receipt_issues(packet, accepted).is_empty())
  guard accepted is Object(fields) else { fail("expected receipt object") }
  fields.remove("review_id")
  fields["accepted"] = Json::boolean(true)
  let issues = review_receipt_issues(packet, accepted)
  assert_true(
    issues.contains(
      "receipt identity must exactly copy request field: review_id",
    ),
  )
}

///|
test "flow adapter gives contract guidance and rejects incomplete drafts" {
  let request : Json = {
    "product_id": "moonmoon",
    "output_contracts": ["moonmoon.scenario-evidence.v1"],
  }
  assert_true(contract_guidance(request).contains("nominal and adverse"))
  let issues = draft_quality_issues(request, {
    "contract_id": "moonmoon.scenario-evidence.v1",
    "product_id": "moonmoon",
    "simulation_model": {},
  })
  assert_true(
    issues.contains("required field is missing or empty: simulation_model"),
  )
  assert_true(
    issues.contains("required field is missing or empty: model_limitations"),
  )
  assert_true(
    issues.contains("required field is missing or empty: uncertainty"),
  )
}

///|
test "flow retry prompt separates rejected drafts from replacement outputs" {
  let request : Json = {
    "product_id": "moontown",
    "output_contracts": ["moontown.deliberation.v1"],
  }
  let prompt = execution_prompt(
    request,
    ["books/robot/flow/drafts/concept.json"],
    2,
    ["MoonTown civic_round requires comparison_criteria"],
  )
  assert_true(prompt.contains("books/robot/flow/drafts/concept.json.prior"))
  assert_true(prompt.contains("one complete replacement JSON object"))
}

///|
test "MoonBook audit preflight requires exact metacognitive gap kinds" {
  let request : Json = {
    "product_id": "moonbook",
    "output_contracts": ["moonbook.outcome-audit.v1"],
    "acceptance_criteria": ["preserve the claim ceiling"],
  }
  let draft : Json = {
    "contract_id": "moonbook.outcome-audit.v1",
    "product_id": "moonbook",
    "criterion_decisions": [
      {
        "criterion": "preserve the claim ceiling",
        "decision": "accepted",
        "evidence_refs": ["evidence/a.json"],
        "rationale": "The evidence remains digital only.",
      },
    ],
    "open_gaps": [
      {
        "type": "information-gap",
        "question": "What remains unknown?",
        "resolution_criteria": ["Collect governed evidence."],
      },
    ],
    "residual_risks": ["model limitations remain"],
    "final_claim": "bounded digital evidence",
    "claim_ceiling": { "level": "scenario-qualified" },
    "recorded_at": "2026-07-12T00:00:00Z",
  }
  let issues = draft_quality_issues(request, draft)
  assert_true(
    issues.contains(
      "MoonBook open gaps require exact kind information-gap, cognition-gap, or execution-gap",
    ),
  )
  assert_true(contract_guidance(request).contains("type is not a substitute"))
  assert_true(
    issues.contains(
      "MoonBook open gaps require string question and resolution_criteria",
    ),
  )
  assert_true(
    issues.contains(
      "MoonBook claim_ceiling must be exactly one scalar string: observation, research-evidence, accepted-knowledge, digital-artifact, simulation-evidence, or scenario-qualified",
    ),
  )
}

///|
test "flow adapter exposes MoonTown emergence boundary without seeding a solution" {
  let request : Json = {
    "product_id": "moontown",
    "output_contracts": ["moontown.deliberation.v1"],
  }
  let guidance = contract_guidance(request)
  assert_true(guidance.contains("uncommissioned contribution"))
  assert_true(guidance.contains("dissenting contribution"))
  assert_false(guidance.contains("polar-inspector"))
  assert_true(guidance.contains("source_book_id"))
  assert_true(guidance.contains("supports"))
  assert_true(guidance.contains("comparison_criteria"))
  assert_true(guidance.contains("comparison_assessments"))
  assert_true(guidance.contains("unresolved_assumptions"))
  let incomplete : Json = {
    "contract_id": "moontown.deliberation.v1",
    "product_id": "moontown",
    "civic_round": {
      "contract_id": "moontown.autonomous-civic-round.v1",
      "contributions": [{ "origin": "emergent" }, { "origin": "dissenting" }],
      "critiques": [{}],
      "rankings": [{}],
      "review": { "decision": "accepted_with_unresolved_dissent" },
      "deliveries": [{}],
    },
  }
  let issues = draft_quality_issues(request, incomplete)
  assert_true(
    issues.contains("MoonTown contribution is missing field: supports"),
  )
  assert_true(
    issues.contains("MoonTown civic_round is missing field: question"),
  )
  assert_true(
    issues.contains(
      "MoonTown civic_round is missing field: comparison_criteria",
    ),
  )
  assert_true(
    issues.contains(
      "MoonTown civic_round is missing field: comparison_assessments",
    ),
  )
  assert_true(
    issues.contains(
      "MoonTown civic_round is missing field: unresolved_assumptions",
    ),
  )
  assert_true(
    issues.contains("MoonTown review decision must be accepted or rejected"),
  )
}

///|
test "MoonClaw software contract requires negative evidence and preserved criteria" {
  let request : Json = {
    "product_id": "moonclaw",
    "output_contracts": ["moonclaw.software-result.v1"],
  }
  assert_true(contract_guidance(request).contains("criteria_preserved"))
  let incomplete : Map[String, Json] = {
    "criteria_preserved": Json::boolean(false),
    "physical_readiness": Json::boolean(false),
  }
  let issues = moonclaw_software_issues(incomplete)
  assert_true(
    issues.contains("MoonClaw software result must preserve all criteria"),
  )
  assert_true(
    issues.contains(
      "MoonClaw software result requires non-empty negative_cases",
    ),
  )
}

///|
test "public web tools are scoped to observe-only MoonWiki evidence work" {
  let research : Json = {
    "product_id": "moonwiki",
    "requested_authority": "observe",
    "output_contracts": ["moonwiki.evidence-bundle.v1"],
  }
  assert_true(request_allows_public_web(research))
  guard research is Object(fields) else { fail("expected request object") }
  fields["requested_authority"] = "workspace-mutation"
  assert_false(request_allows_public_web(research))
  fields["requested_authority"] = "observe"
  fields["product_id"] = "moonrobo"
  assert_false(request_allows_public_web(research))
}

///|
test "MoonWiki research requires successful wrapper-owned search and fetch" {
  let fields : Map[String, Json] = {
    "web_provenance": [
      { "tool": "web_search", "succeeded": true },
      { "tool": "web_fetch", "succeeded": true },
    ],
  }
  assert_true(web_provenance_issues(fields).is_empty())
  fields["web_provenance"] = [{ "tool": "web_search", "succeeded": true }]
  assert_true(
    web_provenance_issues(fields).any(issue => issue.contains("web_fetch")),
  )
}

///|
test "required scalar fields accept numbers and booleans" {
  let fields : Map[String, Json] = {
    "revision": 3,
    "physical_readiness": false,
    "empty": "",
  }
  assert_true(non_empty_field(fields, "revision"))
  assert_true(non_empty_field(fields, "physical_readiness"))
  assert_false(non_empty_field(fields, "empty"))
  assert_false(non_empty_field(fields, "missing"))
}

///|
test "MoonRobo design reports numeric revision before native attestation" {
  let request : Json = {
    "product_id": "moonrobo",
    "output_contracts": ["moonrobo.digital-design.v1"],
  }
  let draft : Json = {
    "contract_id": "moonrobo.digital-design.v1",
    "product_id": "moonrobo",
    "design_id": "generic-design",
    "revision": 1,
    "mission": { "scope": "digital" },
    "task_loop": ["plan", "stop"],
    "mechanisms": [{ "id": "planner" }],
    "validation": { "status": "planned" },
    "constraints": { "physical_readiness": false },
  }
  let issues = draft_quality_issues(request, draft)
  assert_true(issues.any(issue => issue.contains("non-empty string")))
}

///|
test "MoonRobo native design shape passes local validation" {
  let fields : Map[String, Json] = {
    "revision": "r1",
    "mission": { "authority": "digital-only", "robot_class": "survey-rover" },
    "task_loop": ["observe", "plan", "simulate", "safe-stop"],
    "mechanisms": [
      { "id": "mobility", "kind": "locomotion" },
      { "id": "observer", "kind": "sensor" },
      { "id": "supervisor", "kind": "control" },
    ],
    "validation": {
      "scenarios": [
        {
          "id": "nominal",
          "kind": "nominal",
          "expected": "bounded progress",
          "initial_state": { "fresh": true, "safe": true },
          "steps": [
            {
              "step_id": "allow-motion",
              "operation": "boolean_and",
              "inputs": [{ "state": "fresh" }, { "state": "safe" }],
              "output": "motion_allowed",
              "expected": true,
            },
          ],
        },
        {
          "id": "blackout",
          "kind": "negative",
          "expected": "safe stop",
          "initial_state": { "fresh": false, "safe": true },
          "steps": [
            {
              "step_id": "inhibit-motion",
              "operation": "boolean_and",
              "inputs": [{ "state": "fresh" }, { "state": "safe" }],
              "output": "motion_allowed",
              "expected": false,
            },
          ],
        },
        {
          "id": "energy-loss",
          "kind": "degraded",
          "expected": "reserve preserved",
          "initial_state": {
            "energy_wh": 80.0,
            "reserve_wh": 50.0,
            "reserve_safe": false,
          },
          "steps": [
            {
              "step_id": "check-reserve",
              "operation": "greater_or_equal",
              "inputs": [{ "state": "energy_wh" }, { "state": "reserve_wh" }],
              "output": "reserve_preserved",
              "expected": true,
            },
          ],
        },
      ],
    },
    "constraints": {
      "commanded_speed_mps": { "max": 0.1 },
      "safety_predicates": [
        {
          "predicate_id": "fresh-localization",
          "state_key": "fresh",
          "safe_value": true,
          "adverse_scenario_id": "blackout",
        },
        {
          "predicate_id": "reserve-safe",
          "state_key": "reserve_safe",
          "safe_value": true,
          "adverse_scenario_id": "energy-loss",
        },
      ],
    },
    "requirement_traceability": [
      {
        "requirement_id": "req-observe",
        "requirement": "Observe the bounded digital site.",
        "components": ["observer", "supervisor"],
        "verification": ["nominal", "blackout"],
      },
    ],
  }
  assert_true(moonrobo_design_issues(fields).is_empty())
}

///|
test "native helper DSL executes positive and negative vectors" {
  let fields : Map[String, Json] = {
    "change_summary": "Add a reserve margin helper.",
    "implementation": {
      "language": "moonsuite-helper-dsl.v1",
      "functions": [
        {
          "name": "reserve_margin",
          "operation": "subtract",
          "inputs": ["available", "required"],
        },
      ],
    },
    "test_vectors": [
      {
        "case_id": "nominal",
        "function": "reserve_margin",
        "inputs": { "available": 100, "required": 30 },
        "expected": 70,
      },
    ],
    "negative_cases": [
      {
        "case_id": "deficit",
        "function": "reserve_margin",
        "inputs": { "available": 20, "required": 30 },
        "expected": -10,
      },
    ],
    "criteria_preserved": true,
    "physical_readiness": false,
  }
  let result = validate_helper_software_with_criteria(fields, [
    "positive and negative vectors are executed rather than asserted",
  ]).stringify()
  assert_true(result.contains("moonclaw-native-attestor"))
  assert_true(result.contains("\"case_count\":2"))
  assert_true(result.contains("\"physical_readiness\":false"))
  assert_true(result.contains("\"wrapper_owned\":true"))
  assert_true(result.contains("\"inputs\":{\"available\":100"))
  assert_true(result.contains("\"criterion_preservation\":"))
  assert_true(result.contains("\"execution_transcript\":"))
  assert_true(result.contains("\"comparison\":\"exact-json-equality\""))
  assert_true(result.contains("positive and negative vectors are executed"))
}

///|
test "native helper DSL rejects an unproved operation" {
  let fields : Map[String, Json] = {
    "change_summary": "Attempt an unbounded helper.",
    "implementation": {
      "language": "moonsuite-helper-dsl.v1",
      "functions": [
        {
          "name": "unsafe_helper",
          "operation": "execute_shell",
          "inputs": ["left", "right"],
        },
      ],
    },
    "test_vectors": [
      {
        "case_id": "must-refuse",
        "function": "unsafe_helper",
        "inputs": { "left": 1, "right": 2 },
        "expected": 3,
      },
    ],
    "negative_cases": [
      {
        "case_id": "still-must-refuse",
        "function": "unsafe_helper",
        "inputs": { "left": 0, "right": 0 },
        "expected": 0,
      },
    ],
    "criteria_preserved": true,
    "physical_readiness": false,
  }
  let rejected = try {
    ignore(validate_helper_software_with_criteria(fields, []))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "draft validation reports the exact helper DSL shape before attestation" {
  let request : Json = {
    "product_id": "moonclaw",
    "output_contracts": ["moonclaw.software-result.v1"],
  }
  let draft : Json = {
    "contract_id": "moonclaw.software-result.v1",
    "product_id": "moonclaw",
    "change_summary": "Add a bounded helper.",
    "implementation": {
      "contract_id": "moonsuite-helper-dsl.v1",
      "functions": [
        {
          "name": "reserve_margin",
          "inputs": ["available", "required"],
          "expression": { "operation": "subtract" },
        },
      ],
    },
    "test_vectors": [{ "case_id": "nominal" }],
    "negative_cases": [{ "case_id": "deficit" }],
    "criteria_preserved": true,
    "physical_readiness": false,
  }
  let issues = draft_quality_issues(request, draft)
  assert_true(issues.any(issue => issue.contains("moonsuite-helper-dsl.v1")))
  assert_true(issues.any(issue => issue.contains("directly on the function")))
  assert_true(
    issues.any(issue => issue.contains("keyed by function input names")),
  )
}

///|
async test "MoonClaw attestor materializes wrapper-owned helper evidence" {
  let workspace = "/tmp/moonclaw-helper-attestor-wbtest"
  write_json(workspace + "/runtime/request.json", {
    "request_id": "request-helper",
    "product_id": "moonclaw",
    "operation": "implement-helper-tools",
    "output_contracts": ["moonclaw.software-result.v1"],
  })
  write_json(workspace + "/runtime/result.json", {
    "result_id": "result-helper",
    "product_id": "moonclaw",
    "output_digest": "sha256:draft",
    "output_artifacts": ["drafts/helper.json"],
  })
  write_json(workspace + "/drafts/helper.json", {
    "contract_id": "moonclaw.software-result.v1",
    "product_id": "moonclaw",
    "change_summary": "Add a reserve margin helper.",
    "implementation": {
      "language": "moonsuite-helper-dsl.v1",
      "functions": [
        {
          "name": "reserve_margin",
          "operation": "subtract",
          "inputs": ["available", "required"],
        },
      ],
    },
    "test_vectors": [
      {
        "case_id": "nominal",
        "function": "reserve_margin",
        "inputs": { "available": 100, "required": 30 },
        "expected": 70,
      },
    ],
    "negative_cases": [
      {
        "case_id": "deficit",
        "function": "reserve_margin",
        "inputs": { "available": 20, "required": 30 },
        "expected": -10,
      },
    ],
    "criteria_preserved": true,
    "physical_readiness": false,
  })
  attest([
    "--workspace", workspace, "--request", "runtime/request.json", "--result", "runtime/result.json",
    "--attestation", "runtime/attestation.json", "--attestor-id", "moonclaw-native-helper-v1",
    "--draft", "drafts/helper.json", "--final", "outputs/helper.json",
  ])
  let final_output = read_json(workspace + "/outputs/helper.json").stringify()
  assert_true(final_output.contains("moonclaw-native-attestor"))
  assert_true(final_output.contains("\"case_count\":2"))
}
