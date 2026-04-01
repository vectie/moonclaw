///|
test "presentation_deck_spec_schema_prompt names the contract" {
  inspect(
    presentation_deck_spec_schema_prompt().contains(
      presentation_contract_version(),
    ),
    content="true",
  )
}

///|
test "parse_presentation_deck_spec_text parses wrapped JSON" {
  let spec = parse_presentation_deck_spec_text(
    [
      "Here is the deck plan:", "{\"title\":\"Board update\",\"objective\":\"Recommend acquisition\",\"pages\":[{\"page_number\":1,\"page_type\":\"title\",\"headline\":\"Land acquisition\",\"purpose\":\"Open the story\",\"key_message\":\"This is a screening estimate\",\"body_points\":[\"Point A\"],\"evidence\":[\"Source 1\"],\"visual_type\":\"title\",\"layout_instruction\":\"Large title with subtitle\",\"look_and_feel\":\"Clean executive layout\"}],\"render_handoff\":{\"renderer_target\":\"slides-main\",\"theme\":\"board-clean\",\"delivery_notes\":\"Use brand colors\",\"asset_requests\":[\"site map\"]}}",
    ].join("\n\n"),
  )
  inspect(spec is Some(_), content="true")
  inspect(
    spec.map(fn(value) { value.title }).unwrap_or(""),
    content="Board update",
  )
  inspect(
    spec.map(fn(value) { value.pages.length() }).unwrap_or(0).to_string(),
    content="1",
  )
}

///|
test "presentation_render_package_schema_prompt names the render contract" {
  inspect(
    presentation_render_package_schema_prompt().contains(
      presentation_render_contract_version(),
    ),
    content="true",
  )
}

///|
test "parse_presentation_render_package_text parses wrapped JSON" {
  let spec = parse_presentation_render_package_text(
    [
      "Render package follows:", "{\"provider\":\"slides-vendor\",\"renderer_target\":\"slides-main\",\"theme\":\"board-clean\",\"source_plan_contract\":\"presentation_deck_spec.v1\",\"source_plan_artifact\":\"artifact://presentation-plan\",\"output_kind\":\"vendor_handoff\",\"produced_artifacts\":[{\"role\":\"deck_json\",\"path\":\"outputs/presentation/render.json\",\"description\":\"Renderer package\"}],\"handoff_summary\":\"Ready for vendor upload\",\"notes\":[\"Use brand template\"]}",
    ].join("\n"),
  )
  inspect(spec is Some(_), content="true")
  inspect(
    spec.map(fn(value) { value.output_kind }).unwrap_or(""),
    content="vendor_handoff",
  )
  inspect(
    spec
    .map(fn(value) { value.produced_artifacts.length() })
    .unwrap_or(0)
    .to_string(),
    content="1",
  )
}
