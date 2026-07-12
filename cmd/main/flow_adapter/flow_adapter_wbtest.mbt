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
test "flow adapter exposes MoonTown emergence boundary without seeding a solution" {
  let request : Json = {
    "product_id": "moontown",
    "output_contracts": ["moontown.deliberation.v1"],
  }
  let guidance = contract_guidance(request)
  assert_true(guidance.contains("uncommissioned contribution"))
  assert_true(guidance.contains("dissenting contribution"))
  assert_false(guidance.contains("polar-inspector"))
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
