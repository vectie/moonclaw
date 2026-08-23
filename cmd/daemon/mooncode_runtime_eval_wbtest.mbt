///|
async test "mooncode native runtime turn creates eval proof" (t : @test.Test) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-mooncode-runtime-eval-XXXXXX"),
  )
  mooncode_prepare_eval_fixture(book_root)
  let session_id = "session-runtime-eval"
  let command_id = "cmd-runtime-eval"
  let command : Json = {
    "protocol": mooncode_protocol_version(),
    "session_id": session_id,
    "book_root": book_root,
    "command": "run_eval",
    "text": "Run native MoonCode eval proof",
    "packet": {
      "command_id": command_id,
      "action": "run_eval",
      "nearest_module_inventory": [
        "mooncode runtime eval", "native tool harness", "review manifest",
      ],
      "domain_assumptions_reviewed": true,
      "native_check_passed": true,
      "native_tests_passed": true,
      "positive_cases": ["native command ingest", "file edit harness"],
      "negative_cases": ["missing review remains unaccepted"],
      "expected_exit_codes": [0, 1],
      "package_proof_ref": "wiki/reviews/mooncode/package-proof.json",
      "review_receipt_ref": "wiki/reviews/mooncode/review.json",
      "unsupported_claims": [],
      "quality_attempt": 1,
      "input_revision": "r1",
      "quality_output_refs": ["wiki/reviews/mooncode/eval-report.json"],
    },
    "model": "codex/gpt-5.6-sol",
  }
  mooncode_with_fixture_moonfort(book_root, async fn(_) {
    mooncode_append_session_journal(
      book_root,
      session_id,
      mooncode_journal_command(),
      {
        "kind": "mooncode-command",
        "protocol": mooncode_protocol_version(),
        "session_id": session_id,
        "command_id": command_id,
        "created_at": @clock.Timestamp::from_ms(6L),
        "command": command,
      },
    )
    let daemon = Daemon::{
      clock: @clock.epoch,
      models: @model.Loader::new(home=@os.home(), cwd=book_root),
      uuid: @uuid.generator(@rand.chacha8()),
      process: @trusted_host_process.DaemonChildManager::new(cwd=book_root),
      by_cwd: {},
      by_id: {},
      rqs: {},
      httpx: @httpx.Server::new("[::1]", 0, reuse_addr=true),
      port: 0,
      events: @broadcast.Broadcast::new(),
      serve: book_root,
      conversations: @conversation.Manager::new(
        home=book_root,
        uuid=@uuid.generator(@rand.chacha8()),
      ),
      home: book_root,
      pending_codex_auth: {},
      mooncode_sessions: {},
    }
    let result = daemon.mooncode_runtime_turn_execute(session_id, book_root, {
      "consumer_id": "test-runtime",
    })
    assert_true(mooncode_json_bool(result, "accepted", default=false))
    let execution = mooncode_json_object_field_or_empty(result, "execution")
    assert_eq(
      mooncode_json_string(execution, "control", default=""),
      "run_eval",
    )
    let eval_results = mooncode_json_array_items(execution, "eval_results")
    assert_eq(eval_results.length(), 1)
    assert_true(mooncode_json_bool(eval_results[0], "accepted", default=false))
    let manifest_path = mooncode_json_string(
      eval_results[0],
      "manifest_path",
      default="",
    )
    assert_eq(
      manifest_path, "wiki/reviews/mooncode/session-runtime-eval/eval-report.json",
    )
    let manifest_absolute = @pathx.join(book_root, manifest_path)
    assert_true(@fsx.exists(manifest_absolute))
    let manifest_text = @fsx.read_file(manifest_absolute)
    assert_true(manifest_text.contains("\"mooncode-eval-report\""))
    assert_true(manifest_text.contains("\"native_eval_evidence_ready\": true"))
    assert_true(manifest_text.contains("\"quality_qualified\": true"))
    assert_true(manifest_text.contains("\"mooncode.quality-trial.v1\""))
    assert_true(manifest_text.contains("tool_harness"))
    assert_true(manifest_text.contains("file_edit"))
    let events_log = @fsx.read_file(
      mooncode_session_journal_path(book_root, session_id),
    )
    assert_true(events_log.contains("\"eval_report.manifest\""))
    assert_true(events_log.contains("tool_harness"))
    assert_true(events_log.contains("file_edit"))
    let after = mooncode_json_object_field_or_empty(result, "claim_state")
    assert_true(after.stringify().contains("\"delivered_command_count\":1"))
  })
}
