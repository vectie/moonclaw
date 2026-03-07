///|
pub fn SessionManager::count(self : SessionManager) -> Int {
  self.sessions.length()
}

///|
pub fn SessionManager::get(
  self : SessionManager,
  session_key : String,
) -> SessionEntry? {
  self.sessions.get(session_key)
}

///|
pub fn SessionManager::get_or_create(
  self : SessionManager,
  session_key~ : String,
  cwd~ : String,
) -> SessionEntry {
  match self.sessions.get(session_key) {
    Some(entry) => entry
    None => {
      let entry = SessionEntry::{
        session_id: session_key,
        updated_at: 0,
        channel: None,
        model_override: None,
        provider_override: None,
        cwd: Some(cwd),
      }
      self.sessions.set(session_key, entry)
      entry
    }
  }
}

///|
pub fn SessionManager::list(self : SessionManager) -> Array[SessionEntry] {
  self.sessions.values().to_array()
}

///|
pub fn SessionManager::reset(
  self : SessionManager,
  session_key : String,
) -> Bool {
  match self.sessions.get(session_key) {
    Some(_) => {
      self.sessions.remove(session_key)
      true
    }
    None => false
  }
}

///|
pub fn DedupeCache::get(self : DedupeCache, key : String) -> DedupeEntry? {
  self.entries.get(key)
}

///|
pub fn DedupeCache::set(
  self : DedupeCache,
  key : String,
  entry : DedupeEntry,
) -> Unit {
  self.entries.set(key, entry)
}

///|
pub fn DedupeCache::clear_expired(self : DedupeCache, now_ms : Int) -> Unit {
  let expired_keys : Array[String] = []
  for key, entry in self.entries {
    if now_ms - entry.ts > self.ttl_ms {
      expired_keys.push(key)
    }
  }
  for key in expired_keys {
    self.entries.remove(key)
  }
}
