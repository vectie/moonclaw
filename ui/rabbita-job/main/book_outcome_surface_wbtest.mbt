///|
test "Book handoff UI names exact source limits and keeps detailed source collapsed" {
  let snapshot = test_canvas_snapshot([])
  let view = @rabbita.render_to_string(
    @rabbita.static_cell(render_book_outcome_panel(snapshot)),
  )
  assert_true(view.contains("Send completed output to Book"))
  assert_true(view.contains("8 MiB"))
  assert_true(view.contains("claw-book-freeze"))
  assert_true(view.contains("claw-book-receipt"))
  assert_true(view.contains("claw-book-recovery-open"))
  assert_true(view.contains("Three-Gap"))
  assert_false(view.contains("<details open"))
}

///|
#cfg(target="js")
extern "js" fn test_book_gateway(install : (String) -> Unit) -> @js.Promise =
  #| async (install) => {
  #|   const base = process.env.MOONCLAW_BOOK_HTTP_URL;
  #|   if (!base || !/^http:\/\/127\.0\.0\.1:\d+$/.test(base)) throw new Error('Native fixture gateway URL required');
  #|   const original = globalThis.fetch;
  #|   try {
  #|     delete globalThis.__moonclawTransport; install(base);
  #|     const module = await import('file://' + process.cwd() + '/book-outcome-http-fixture.mjs');
  #|     await module.verifyGatewayBookHandoff(base);
  #|     return 'ACTUAL_BOOK_GATEWAY_UI_PASSED';
  #|   } finally { globalThis.__moonclawTransport?.clear(); delete globalThis.__moonclawTransport; globalThis.fetch = original; }
  #| }

///|
#skip("Run through isolated native Book gateway fixture")
test "Book source UI uses actual authenticated gateway and exact native bytes" {
  @js.async_test(() => {
    let result : String = test_book_gateway(configure_gateway_transport)
      .wait()
      .cast()
    assert_eq(result, "ACTUAL_BOOK_GATEWAY_UI_PASSED")
    println(result)
  })
}
