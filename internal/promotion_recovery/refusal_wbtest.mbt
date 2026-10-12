///|
async test "recovery never follows a checkpoint symlink or inspects terminal corrupt oversized records" {
  @fsx.with_temporary_directory("recovery-refusal-XXXXXX", async fn(root) {
    let path = recovery_test_pending(root)
    let original = @fs.read_file(path).binary()
    let request = recovery_test_request()
    let calls = Ref(0)
    let invoke = async fn(_retention) {
      calls.val += 1
      recovery_test_response("desired-applied")
    }
    for contents in [
      "{partial",
      "x".repeat(131_073),
      ({ "request": recovery_test_selection().to_json(), "pending_attempt": false } : Json).stringify(),
    ] {
      @fs.write_file(path, contents)
      assert_true((try? moondesk_recovery_inspect(request, root, invoke)) is Err(_))
      assert_eq(@fs.read_file(path).text(), contents)
    }
    @fs.remove(path)
    let target = root + "/CANARY-private-record"
    @fs.write_file(target, original, create_mode=CreateNew, permission=0o600)
    @fs.symlink(path, target~)
    assert_true((try? moondesk_recovery_inspect(request, root, invoke)) is Err(_))
    assert_eq(@fs.read_file(target).binary(), original)
    assert_eq(calls.val, 0)
  })
}
