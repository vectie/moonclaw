///|
/// Shared identity of the canonical contract written by current MoonCode.
pub fn journal_contract_id() -> String {
  "moonsuite-conversation-journal.v2"
}

///|
/// Canonical physical contracts accepted during replay, oldest first.
pub fn journal_read_contract_ids() -> Array[String] {
  [@conversation.journal_contract_id(), journal_contract_id()]
}
