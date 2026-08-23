///|
test "goal journal record identity uses canonical event_id" {
  let a = mooncode_journal_record_id(mooncode_journal_goal_event(), {
    "kind": "mooncode.goal.changed",
    "event_id": "a",
    "timestamp": 1,
  })
  let b = mooncode_journal_record_id(mooncode_journal_goal_event(), {
    "kind": "mooncode.goal.changed",
    "event_id": "b",
    "timestamp": 1,
  })
  inspect(a, content="event:a")
  inspect(b, content="event:b")
}

///|
test "goal journal record identity is timestamp independent" {
  let first = mooncode_journal_record_id(mooncode_journal_goal_event(), {
    "kind": "mooncode.goal.changed",
    "event_id": "same",
    "timestamp": 1,
  })
  let second = mooncode_journal_record_id(mooncode_journal_goal_event(), {
    "kind": "mooncode.goal.changed",
    "event_id": "same",
    "timestamp": 2,
  })
  inspect(first == second, content="true")
  inspect(first, content="event:same")
}

///|
test "goal journal record identity rejects blank event_id" {
  try
    mooncode_journal_record_id(mooncode_journal_goal_event(), {
      "kind": "mooncode.goal.changed",
      "event_id": "",
      "timestamp": 1,
    })
  catch {
    InvalidJournal(_) => ()
  } noraise {
    _ => fail("expected InvalidJournal")
  }
}

///|
test "goal journal record identity rejects padded event_id" {
  try
    mooncode_journal_record_id(mooncode_journal_goal_event(), {
      "kind": "mooncode.goal.changed",
      "event_id": " padded ",
      "timestamp": 1,
    })
  catch {
    InvalidJournal(_) => ()
  } noraise {
    _ => fail("expected InvalidJournal")
  }
}

///|
test "unrelated event retains timestamp fallback identity" {
  let id = mooncode_journal_record_id(mooncode_journal_event(), {
    "kind": "other.event",
    "timestamp": "2025-01-01T00:00:00Z",
  })
  inspect(id, content="event::other.event:null")
}
