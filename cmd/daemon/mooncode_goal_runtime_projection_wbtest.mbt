///|
async fn goal_projection_write_record(
  writer : @fs.File,
  carrier : MoonCodeGoalRuntimeCarrier,
  sequence : Int,
) -> Unit {
  writer.write(
    scan_test_record_v2(carrier, sequence.to_string()).stringify() + "\n",
  )
}

///|
async test "streaming goal projection keeps constant heap across a large journal" {
  @moonclaw_fsx.with_temporary_directory(
    "moonclaw-goal-projection-test-XXXXXX",
    async fn(root) {
      let path = @pathx.join(root, "journal.jsonl")
      let writer = @fs.open(
        path,
        mode=ReadWrite,
        append=true,
        create_mode=OpenOrCreate,
        permission=0o600,
      )
      goal_projection_write_record(writer, scan_test_carrier(), 1)
      let count = 20000
      for i in 0..<count {
        let stored = carrier_test_event(
          PhaseChanged("large-event-" + i.to_string(), Running),
          2L,
        )
        let canonical = encode_mooncode_goal_runtime_stored_event(stored)
        goal_projection_write_record(
          writer,
          mooncode_goal_runtime_carrier_from_event(canonical),
          i + 2,
        )
      }
      let duplicate = carrier_test_event(
        PhaseChanged("large-event-0", Running),
        99L,
      )
      goal_projection_write_record(
        writer,
        mooncode_goal_runtime_carrier_from_event(
          encode_mooncode_goal_runtime_stored_event(duplicate),
        ),
        count + 2,
      )
      writer.close()
      let reader = @fs.open(path, mode=ReadOnly)
      defer reader.close()
      let authority = mooncode_goal_authority_project_file(
        reader,
        "session-你好",
        target_runtime_id=Some("large-event-0"),
      )
      assert_false(mooncode_goal_authority_projection_is_dual(authority))
      assert_true(authority.legacy is None)
      assert_eq(authority.runtime.cursor.text(), (count + 2).to_string())
      assert_eq(authority.runtime.handled_count.text(), count.to_string())
      assert_eq(authority.runtime.operation_count.text(), "0")
      assert_eq(authority.runtime.checkpoint_count.text(), "0")
      assert_true(authority.runtime.target_digest is Some(_))
      assert_false(authority.runtime.terminal)
    },
  )
}

///|
async test "streaming goal projection detects far semantic identity conflict" {
  @moonclaw_fsx.with_temporary_directory(
    "moonclaw-goal-projection-conflict-XXXXXX",
    async fn(root) {
      let path = @pathx.join(root, "journal.jsonl")
      let writer = @fs.open(
        path,
        mode=ReadWrite,
        append=true,
        create_mode=OpenOrCreate,
        permission=0o600,
      )
      goal_projection_write_record(writer, scan_test_carrier(), 1)
      let first = carrier_test_event(PhaseChanged("stable-id", Running), 2L)
      goal_projection_write_record(
        writer,
        mooncode_goal_runtime_carrier_from_event(
          encode_mooncode_goal_runtime_stored_event(first),
        ),
        2,
      )
      for i in 0..<1000 {
        let middle = carrier_test_event(
          PhaseChanged("middle-" + i.to_string(), Running),
          3L,
        )
        goal_projection_write_record(
          writer,
          mooncode_goal_runtime_carrier_from_event(
            encode_mooncode_goal_runtime_stored_event(middle),
          ),
          i + 3,
        )
      }
      let conflict = carrier_test_event(
        PhaseChanged("stable-id", WaitingApproval),
        4L,
      )
      goal_projection_write_record(
        writer,
        mooncode_goal_runtime_carrier_from_event(
          encode_mooncode_goal_runtime_stored_event(conflict),
        ),
        1003,
      )
      writer.close()
      let reader = @fs.open(path, mode=ReadOnly)
      defer reader.close()
      let rejected = try {
        ignore(mooncode_goal_authority_project_file(reader, "session-你好"))
        false
      } catch {
        MoonCodeGoalRuntimeStoreError::IdentityConflict(id, _, _) =>
          id == "stable-id"
        _ => false
      }
      assert_true(rejected)
    },
  )
}
