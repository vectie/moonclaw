///|
async test "mooncode parallel read benchmark preserves results across a cached batch" {
  @fsx.with_temporary_directory("mooncode-parallel-benchmark-XXXXXX", async fn(
    root,
  ) {
    let calls : Array[Json] = []
    let payload = "0123456789abcdef".repeat(32768)
    for index in 0..<8 {
      let path = "fixture-\{index}.txt"
      @fsx.write_to_file(@pathx.join(root, path), payload + "\n\{index}\n")
      calls.push({ "tool": "read", "arguments": { "path": path } })
    }
    let command : Json = {
      "command": "prompt",
      "session_id": "parallel-benchmark-session",
      "book_root": root,
      "packet": { "command_id": "parallel-benchmark-command" },
    }
    let daemon = mooncode_control_test_daemon(root)
    // Warm the filesystem cache so this benchmark measures harness overhead,
    // not whichever path happened to cause the first disk fetch.
    ignore(
      daemon.mooncode_runtime_turn_execute_parallel_reads(
        command, "parallel-benchmark-session", root, calls,
      ),
    )
    let sequential_started = @clock.epoch.now()
    let sequential : Array[Json] = []
    for _ in 0..<8 {
      for call in calls {
        sequential.push(
          mooncode_execute_tool_call(
            "parallel-benchmark-session",
            root,
            mooncode_runtime_turn_tool_body(command, call),
            now=@clock.epoch.now(),
          ),
        )
      }
    }
    let sequential_ms = @clock.epoch.now().ms_since(sequential_started).to_int()
    let parallel_started = @clock.epoch.now()
    let parallel : Array[Json] = []
    for _ in 0..<8 {
      for
        result in daemon.mooncode_runtime_turn_execute_parallel_reads(
          command, "parallel-benchmark-session", root, calls,
        ) {
        parallel.push(result)
      }
    }
    let parallel_ms = @clock.epoch.now().ms_since(parallel_started).to_int()
    assert_eq(sequential.length(), parallel.length())
    for index in 0..<sequential.length() {
      let sequential_result = mooncode_json_object_field_or_empty(
        sequential[index],
        "result",
      )
      let parallel_result = mooncode_json_object_field_or_empty(
        parallel[index],
        "result",
      )
      assert_eq(
        mooncode_json_string(sequential_result, "output", default=""),
        mooncode_json_string(parallel_result, "output", default=""),
      )
      assert_eq(
        mooncode_json_object_field_or_empty(sequential_result, "metadata"),
        mooncode_json_object_field_or_empty(parallel_result, "metadata"),
      )
    }
    println(
      (
        {
          "contract": "moonclaw.parallel-read-benchmark.v1",
          "file_count": calls.length(),
          "file_chars": payload.length(),
          "iterations": 8,
          "sequential_ms": sequential_ms,
          "parallel_ms": parallel_ms,
        } : Json).stringify(),
    )
  })
}
