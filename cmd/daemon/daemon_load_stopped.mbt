///|
/// Loads all existing stopped conversations from storage and adds them as
/// stopped tasks to the daemon.
///
/// Parameters:
///
/// * `self` : The daemon instance to load conversations into.
async fn Daemon::load_stopped(self : Daemon) -> Unit {
  let ids = self.conversations.list()
  let id_strings = ids.map(fn(id) { id.to_string() })
  logger.info("Loading existing conversations: \{id_strings.join(", ")}")
  for id in ids {
    guard self.conversations.load(id) is Some(conversation) else {
      logger.warn("Failed to load conversation '\{id}', skipping...")
      continue
    }
    logger.info(
      "Loaded conversation '\{conversation.id()}' at cwd '\{conversation.cwd()}'",
    )
    let cwd = conversation.cwd()
    let id = conversation.id()
    if self.by_id.get(id) is Some(_) {
      continue
    }
    let broadcast : @broadcast.Broadcast[@server.ServerStreamEvent] = @broadcast.Broadcast::new()
    for event in conversation.events() {
      broadcast.put(Moonclaw(event))
    }
    let task : Stopped = {
      name: Some(conversation.name()),
      id,
      cwd,
      created: conversation.created(),
      updated: conversation.updated(),
      web_search: conversation.web_search(),
      broadcast,
      source_kind: conversation.source_kind(),
      workspace_trust: conversation.workspace_trust(),
    }
    self.by_id[id] = Stopped(task)
  }
}
