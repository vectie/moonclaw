///|
async test "truncate_string/zero_negative_exact_and_unicode_boundaries" (
  t : @test.Test,
) {
  @mock.run(t, mock => {
    let counter = Counter::new(logger=mock.logger)
    assert_eq(counter.truncate_string("plain ascii", 0), "")
    assert_eq(counter.truncate_string("plain ascii", -1), "")
    assert_eq(counter.truncate_string("plain ascii", 100), "plain ascii")

    let source = "汉字🙂é🌙🚀مرحبا".repeat(80)
    let source_tokens = counter.count_string(source) - 7
    assert_eq(counter.truncate_string(source, source_tokens), source)
    let shortened = counter.truncate_string(source, source_tokens - 1)
    assert_true(shortened != source)
    assert_true(shortened.has_suffix(" …"))
    assert_false(shortened.contains("�"))

    let mut previous_length = 0
    for max_tokens in 1..<=64 {
      let first = counter.truncate_string(source, max_tokens)
      let second = counter.truncate_string(source, max_tokens)
      guard first == second else {
        fail("unicode truncation was nondeterministic at \{max_tokens}")
      }
      guard !first.contains("�") else {
        fail("unicode truncation produced replacement text at \{max_tokens}")
      }
      guard first.has_suffix(" …") else {
        fail("unicode truncation omitted marker at \{max_tokens}")
      }
      guard first.length() >= previous_length else {
        fail("unicode prefix shrank at \{max_tokens}")
      }
      // The marker itself may consume a few extra tokens; the decoded source
      // prefix remains capped by max_tokens.
      guard counter.count_string(first) <= max_tokens + 10 else {
        fail(
          "unicode truncation exceeded bounded marker overhead at \{max_tokens}",
        )
      }
      previous_length = first.length()
    }
  })
}
