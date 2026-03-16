///|
test "merged_acp_linkage_metadata inherits session linkage when request metadata is missing" {
  inspect(
    merged_acp_linkage_metadata(
      {
        "linked_job_run_id": "run-1",
        "linked_job_id": "job-1",
        "linked_job_node_id": "node-1",
        "linked_job_step_id": "step-1",
        "linked_workspace": "/tmp/workspace",
        "thread_id": "thread-1",
      },
      None,
    )
    .unwrap()
    .stringify(),
    content="{\"linked_job_run_id\":\"run-1\",\"linked_job_id\":\"job-1\",\"linked_job_node_id\":\"node-1\",\"linked_job_step_id\":\"step-1\",\"linked_workspace\":\"/tmp/workspace\",\"thread_id\":\"thread-1\"}",
  )
}

///|
test "merged_acp_linkage_metadata keeps explicit request fields and fills missing session fields" {
  inspect(
    merged_acp_linkage_metadata(
      {
        "linked_job_run_id": "run-session",
        "linked_job_id": "job-session",
        "linked_job_node_id": "node-session",
        "thread_id": "thread-1",
      },
      Some({
        "linked_job_run_id": "run-request",
        "linked_job_step_id": "step-request",
      }),
    )
    .unwrap()
    .stringify(),
    content="{\"linked_job_run_id\":\"run-request\",\"linked_job_step_id\":\"step-request\",\"linked_job_id\":\"job-session\",\"linked_job_node_id\":\"node-session\",\"thread_id\":\"thread-1\"}",
  )
}
