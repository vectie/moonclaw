///|
test "durable terminal failure takes precedence over earlier assistant answer" {
  let turn = mooncode_conversation_turn_draft(
    turn_id="cmd-1",
    client_turn_id="client-1",
    command_id="cmd-1",
    created_at="2026-09-26T00:00:00Z",
  )
  let assistant : Json = {
    "role": "assistant",
    "content": "A partial answer",
    "status": "done",
  }
  turn.status = "failed"
  assert_eq(mooncode_conversation_final_status(turn, assistant), "failed")
  turn.status = "cancelled"
  assert_eq(mooncode_conversation_final_status(turn, assistant), "cancelled")
}
