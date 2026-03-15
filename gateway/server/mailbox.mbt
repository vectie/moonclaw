///|
pub struct AgentMailbox {
  agent_id : String
  config : AgentMailboxConfig
  created_at : Int
  mut last_read_at : Int?
  mut message_count : Int
  priv queue : @aqueue.Queue[AgentMessage]
}

///|
pub fn agent_mailbox(
  agent_id~ : String,
  config? : AgentMailboxConfig = agent_mailbox_config(),
  timestamp? : Int = 0,
) -> AgentMailbox {
  let kind = match config.max_size {
    0 => @aqueue.Unbounded
    n => @aqueue.DiscardOldest(n)
  }
  AgentMailbox::{
    agent_id,
    queue: @aqueue.Queue::new(kind~),
    config,
    created_at: timestamp,
    last_read_at: None,
    message_count: 0,
  }
}

///|
pub async fn AgentMailbox::put(
  self : AgentMailbox,
  message : AgentMessage,
) -> Unit {
  self.queue.put(message)
  self.message_count = self.message_count + 1
}

///|
pub fn AgentMailbox::try_put(
  self : AgentMailbox,
  message : AgentMessage,
) -> Bool {
  try {
    let result = self.queue.try_put(message)
    if result {
      self.message_count = self.message_count + 1
    }
    result
  } catch {
    _ => false
  }
}

///|
pub async fn AgentMailbox::get(self : AgentMailbox) -> AgentMessage {
  let msg = self.queue.get()
  self.last_read_at = Some(msg.timestamp)
  msg
}

///|
pub fn AgentMailbox::try_get(self : AgentMailbox) -> AgentMessage? {
  try {
    let result = self.queue.try_get()
    match result {
      Some(msg) => {
        self.last_read_at = Some(msg.timestamp)
        Some(msg)
      }
      None => None
    }
  } catch {
    _ => None
  }
}

///|
pub fn AgentMailbox::message_count(self : AgentMailbox) -> Int {
  self.message_count
}

///|
pub fn AgentMailbox::close(self : AgentMailbox) -> Unit {
  self.queue.close()
}

///|
pub fn AgentMailbox::to_json(self : AgentMailbox) -> Json {
  {
    "agent_id": self.agent_id.to_json(),
    "config": self.config.to_json(),
    "created_at": self.created_at.to_json(),
    "last_read_at": self.last_read_at.to_json(),
    "message_count": self.message_count.to_json(),
  }
}

///|
pub struct MailboxManager {
  config : AgentMailboxConfig
  priv mailboxes : Map[String, AgentMailbox]
}

///|
pub fn mailbox_manager(
  config? : AgentMailboxConfig = agent_mailbox_config(),
) -> MailboxManager {
  MailboxManager::{ mailboxes: Map::new(), config }
}

///|
pub fn MailboxManager::create(
  self : MailboxManager,
  agent_id : String,
  timestamp? : Int = 0,
) -> AgentMailbox {
  let mailbox = agent_mailbox(agent_id~, config=self.config, timestamp~)
  self.mailboxes.set(agent_id, mailbox)
  mailbox
}

///|
pub fn MailboxManager::get(
  self : MailboxManager,
  agent_id : String,
) -> AgentMailbox? {
  self.mailboxes.get(agent_id)
}

///|
pub fn MailboxManager::remove(
  self : MailboxManager,
  agent_id : String,
) -> AgentMailbox? {
  let mailbox = self.mailboxes.get(agent_id)
  match mailbox {
    Some(m) => {
      m.close()
      self.mailboxes.remove(agent_id)
      Some(m)
    }
    None => None
  }
}

///|
pub fn MailboxManager::has(self : MailboxManager, agent_id : String) -> Bool {
  self.mailboxes.contains(agent_id)
}

///|
pub fn MailboxManager::list(self : MailboxManager) -> Array[String] {
  self.mailboxes.keys().to_array()
}

///|
pub fn MailboxManager::size(self : MailboxManager) -> Int {
  self.mailboxes.length()
}

///|
pub async fn MailboxManager::deliver(
  self : MailboxManager,
  message : AgentMessage,
) -> Unit {
  match message.to_agent {
    Some(target_id) =>
      match self.mailboxes.get(target_id) {
        Some(mailbox) => mailbox.put(message)
        None => ()
      }
    None =>
      for mailbox in self.mailboxes.values() {
        if mailbox.agent_id != message.from_agent {
          mailbox.put(message)
        }
      }
  }
}

///|
pub fn MailboxManager::deliver_sync(
  self : MailboxManager,
  message : AgentMessage,
) -> Int {
  let mut delivered = 0
  match message.to_agent {
    Some(target_id) =>
      match self.mailboxes.get(target_id) {
        Some(mailbox) => if mailbox.try_put(message) { delivered = 1 }
        None => ()
      }
    None =>
      for mailbox in self.mailboxes.values() {
        if mailbox.agent_id != message.from_agent {
          if mailbox.try_put(message) {
            delivered = delivered + 1
          }
        }
      }
  }
  delivered
}

///|
pub fn MailboxManager::to_json(self : MailboxManager) -> Json {
  {
    "config": self.config.to_json(),
    "mailbox_count": self.mailboxes.length().to_json(),
    "agents": self.mailboxes.keys().to_array().to_json(),
  }
}
