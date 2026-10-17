///|
test "Use what worked is reachable in the existing Work screen and never starts execution" {
  let model = cowork_request_test_ready("procedure-thread")
  let html = @rabbita.render_to_string(
    @rabbita.static_cell(
      render_cowork_center(@cmd.Emit(_ => @rabbita.none), model),
    ),
  )
  assert_true(html.contains("Use what worked"))
  assert_true(html.contains("Load accepted procedures"))
  assert_true(html.contains("Use selected approach in draft"))
  assert_true(html.contains("Compare with linked result"))
  assert_true(html.contains("claw-procedure-composer"))
  assert_true(html.contains("Choosing a method does not start a run"))
  assert_false(html.contains("<details open"))
  let loading = { ..model, cowork_detail_loading: true, }
  let hidden = @rabbita.render_to_string(
    @rabbita.static_cell(render_cowork_procedures(loading)),
  )
  assert_false(hidden.contains("claw-procedure-load"))
}
