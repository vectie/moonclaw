///|
async test "operator procedures reuse accepted-memory capture and preserve exact source" {
  @fsx.with_temporary_directory("claw-procedure-choice-XXXXXX", dir => {
    let root = dir.to_string()
    @fs.mkdir(root + "/memory/procedures", recursive=true)
    @fs.mkdir(root + "/memory/beliefs", recursive=true)
    let accepted = "{\"status\":\"accepted\",\"title\":\"Fixture procedure 世界\",\"effort\":{\"runtime_ms\":100},\"outcome\":\"Fixture evidence only\"}"
    @fs.write_file(
      root + "/memory/procedures/accepted.json",
      accepted,
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      root + "/memory/procedures/rejected.json",
      "{\"status\":\"rejected\",\"accepted\":true}",
      create_mode=CreateOrTruncate,
    )
    @fs.write_file(
      root + "/memory/beliefs/accepted.json",
      "{\"status\":\"accepted\"}",
      create_mode=CreateOrTruncate,
    )
    let binding : @book_learning.Binding = {
      workspace_id: "fixture-session",
      book_id: "cowork-selected-workspace",
      source_root: root,
      request_digest: @book_learning.digest(b"fixture"),
    }
    let snapshot = @book_learning.capture(binding, 1)
    assert_eq(snapshot.records.length(), 2)
    let projected = cowork_procedure_projection(
      "fixture-session", root, snapshot,
    )
    guard projected
      is {
        "records": Array([record]),
        "authority_granted": False,
        "status": String("ready"),
        ..
      } else {
      fail("Expected one captured procedure without authority")
    }
    assert_true(
      record
      is {
        "path": String("memory/procedures/accepted.json"),
        "content_utf8": String(content),
        ..
      } &&
      content == accepted,
    )
    assert_eq(
      @fs.read_file(root + "/memory/procedures/accepted.json").text(),
      accepted,
    )
    @fs.write_file(
      root + "/memory/procedures/accepted.json",
      "{\"status\":\"rejected\"}",
      create_mode=CreateOrTruncate,
    )
    let updated = cowork_procedure_projection(
      "fixture-session",
      root,
      @book_learning.capture(binding, 2),
    )
    assert_true(updated is { "records": Array([]), .. })
    assert_true(projected is { "records": Array([_]), .. })
  })
}

///|
test "private procedure routes remain inside gateway authentication" {
  let path = "/v1/cowork/sessions/fixture/procedures"
  assert_false(gateway_http_authorized(path, {}, Some("fixture-token")))
  assert_true(
    gateway_http_authorized(
      path,
      { "authorization": "Bearer fixture-token" },
      Some("fixture-token"),
    ),
  )
}
