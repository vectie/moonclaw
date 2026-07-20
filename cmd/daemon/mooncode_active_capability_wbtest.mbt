///|
async test "MoonCode resolves MoonFlow canary projection before planning" (
  t : @test.Test,
) {
  ignore(t)
  let book_root = @fsx.mkdtemp(
    @pathx.join(@os.tmpdir(), "moonclaw-capability-loop-XXXXXX"),
  )
  let directory = @pathx.join(
    book_root, ".moonsuite/products/moonflow/capabilities",
  )
  @fsx.make_directory(directory, recursive=true, exists_ok=true)
  let projection : Json = {
    "contract_version": "moonflow.capability_loop.v1",
    "activation_id": "activation-1",
    "scope_id": "wiki-maintainer",
    "rollout_mode": "canary",
    "status": "active",
    "challenger_participant_ids": ["session-canary"],
    "old_capability": {
      "record_id": "capability",
      "record_version": "4",
      "record_digest": "sha256:capability:4",
    },
    "new_capability": {
      "record_id": "capability",
      "record_version": "5",
      "record_digest": "sha256:capability:5",
    },
    "experiment": {
      "record_id": "experiment",
      "record_version": "1",
      "record_digest": "sha256:experiment:1",
    },
  }
  @fsx.write_to_file(
    @pathx.join(directory, "wiki-maintainer.json"),
    projection.stringify(),
  )
  let resolved = mooncode_runtime_turn_attach_active_capability(
    book_root,
    "session-canary",
    { "capability_scope_id": "wiki-maintainer" },
  )
  let active = mooncode_json_object_field_or_empty(
    resolved, "active_capability",
  )
  assert_eq(
    mooncode_json_string(active, "assignment", default=""),
    "challenger",
  )
  assert_eq(
    mooncode_json_string(
      mooncode_json_object_field_or_empty(active, "selected_capability"),
      "record_version",
      default="",
    ),
    "5",
  )
}
