///|
test "delegate provider receipt uses object-or-null wire shape" {
  json_inspect(supervisor_provider_receipt_json(None), content=null)
  let receipt : @job.SupervisorCommandReceiptV1 = {
    contract_id: "moonclaw.supervisor-command-receipt.v1",
    command_id: "provider.accepted.worker.1",
    request_digest: "sha256:request",
    supervisor_id: "bo-supervisor",
    cursor: 2,
    event_id: "bo-supervisor:2",
    status: "accepted",
    duplicate: false,
    response: { "execution_status": "running" },
  }
  json_inspect(supervisor_provider_receipt_json(Some(receipt)), content={
    "contract_id": "moonclaw.supervisor-command-receipt.v1",
    "command_id": "provider.accepted.worker.1",
    "request_digest": "sha256:request",
    "supervisor_id": "bo-supervisor",
    "cursor": 2,
    "event_id": "bo-supervisor:2",
    "status": "accepted",
    "duplicate": false,
    "response": { "execution_status": "running" },
  })
}
