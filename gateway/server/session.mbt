///|
struct PersistedSession {
  session_key : String
  entry : SessionEntry
} derive(ToJson, FromJson, Show)

///|
fn SessionManager::store_file(self : SessionManager) -> String {
  @path.Path(self.session_dir).join(@path.Path("sessions.json")).to_string()
}

///|
pub async fn SessionManager::load(self : SessionManager) -> Unit {
  let store_file = self.store_file()
  if !@fsx.exists(store_file) {
    return
  }
  let content = @fsx.read_file(store_file)
  let sessions : Array[PersistedSession] = @json.from_json(@json.parse(content)) catch {
    error =>
      fail("Failed to load gateway sessions from \{store_file}: \{error}")
  }
  let existing_keys = self.sessions.keys().to_array()
  for key in existing_keys {
    self.sessions.remove(key)
  }
  for persisted in sessions {
    self.sessions.set(persisted.session_key, persisted.entry)
  }
}

///|
pub async fn SessionManager::save(self : SessionManager) -> Unit {
  @fsx.make_directory(self.session_dir, recursive=true) catch {
    _ => ()
  }
  let sessions : Array[PersistedSession] = []
  for session_key, entry in self.sessions {
    sessions.push(PersistedSession::{ session_key, entry })
  }
  let content = sessions.to_json().stringify()
  @fsx.write_to_file(self.store_file(), content)
}

///|
pub async fn SessionManager::save_entry(
  self : SessionManager,
  session_key : String,
  entry : SessionEntry,
) -> Unit {
  self.sessions.set(session_key, entry)
  self.save()
}

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
        updated_at: current_time_ms(),
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
pub async fn SessionManager::reset_and_save(
  self : SessionManager,
  session_key : String,
) -> Bool {
  let removed = self.reset(session_key)
  if removed {
    self.save()
  }
  removed
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
