///|
/// Preview exact-ID intake and reader annotation conflicts without changing either archive.
pub fn ReadingShortlist::preview_merge(
  self : ReadingShortlist,
  incoming : ReadingShortlist,
) -> Json {
  let existing : Map[String, ShortlistEntry] = Map([])
  for entry in self.entries {
    existing[entry.entry_id] = entry
  }
  let added : Array[String] = []
  let conflicts : Array[Json] = []
  let mut shared = 0
  for entry in incoming.entries {
    match existing.get(entry.entry_id) {
      None => added.push(entry.entry_id)
      Some(old) => {
        shared += 1
        if old.state != entry.state || old.note != entry.note {
          conflicts.push({
            "entry_id": entry.entry_id,
            "title": old.snapshot.article.title,
            "existing": { "state": old.state, "note": old.note },
            "incoming": { "state": entry.state, "note": entry.note },
          })
        }
      }
    }
  }
  {
    "retained_title": self.title,
    "incoming_title": incoming.title,
    "existing_count": self.entries.length(),
    "shared_count": shared,
    "added_ids": added,
    "merged_count": self.entries.length() + added.length(),
    "within_article_limit": self.entries.length() + added.length() <= 1000,
    "annotation_conflicts": conflicts,
  }
}

///|
/// Union frozen catalogs and selections by exact snapshot ID. The receiver's
/// title, catalog order and selected order come first. Different observations
/// never match by publisher ID or URL. Conflict policy applies to the entire
/// state/note pair, including explicit empty notes and unread state.
pub fn ReadingShortlist::merge(
  self : ReadingShortlist,
  incoming : ReadingShortlist,
  conflict~ : String = "error",
) -> ReadingShortlist raise {
  guard conflict is ("error" | "keep-existing" | "use-incoming") else {
    fail("Merge conflict policy must be error, keep-existing or use-incoming")
  }
  let entries = self.entries.copy()
  let positions : Map[String, Int32] = Map([])
  for index, entry in entries {
    positions[entry.entry_id] = index
  }
  for entry in incoming.entries {
    match positions.get(entry.entry_id) {
      None => {
        guard entries.length() < 1000 else {
          fail("Merged shortlist exceeds 1000 captured articles")
        }
        positions[entry.entry_id] = entries.length()
        entries.push(entry)
      }
      Some(index) => {
        let old = entries[index]
        if old.state != entry.state || old.note != entry.note {
          match conflict {
            "error" =>
              fail(
                "Annotation conflict for \{entry.entry_id}; inspect-merge before choosing keep-existing or use-incoming",
              )
            "use-incoming" => entries[index] = entry
            _ => ()
          }
        }
      }
    }
  }
  let order = self.order.copy()
  let selected : Map[String, Bool] = Map([])
  for id in order {
    selected[id] = true
  }
  for id in incoming.order {
    if !selected.contains(id) {
      selected[id] = true
      order.push(id)
    }
  }
  let result = ReadingShortlist::{ title: self.title, entries, order, }
  ignore(result.to_archive())
  result
}
