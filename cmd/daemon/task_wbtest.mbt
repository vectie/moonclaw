///|
test "Task::to_json for Running variant" {
  let running = Running::{
    name: Some("running-task"),
    id: @uuid.parse("123e4567-e89b-12d3-a456-426614174000"),
    cwd: "/tmp/running",
    port: 8080,
    status: Idle,
    queued_messages: [],
    created: @clock.Timestamp::from_ms(1000),
    updated: @clock.Timestamp::from_ms(2000),
    web_search: false,
    model: "gpt-4",
    broadcast: @broadcast.Broadcast::new(),
  }
  let task = Task::Running(running)
  let json = task.to_json()
  // Task::to_json delegates to Running::to_json
  guard json
    is {
      "status": "idle",
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "cwd": "/tmp/running",
      "port": 8080,
      "name": "running-task",
      ..
    } else {
    fail("Unexpected JSON structure")
  }
}

///|
test "Task::to_json for Stopped variant" {
  let stopped = Stopped::{
    name: Some("stopped-task"),
    id: @uuid.parse("223e4567-e89b-12d3-a456-426614174000"),
    cwd: "/tmp/stopped",
    created: @clock.Timestamp::from_ms(1000),
    updated: @clock.Timestamp::from_ms(2000),
    web_search: true,
    broadcast: @broadcast.Broadcast::new(),
  }
  let task = Task::Stopped(stopped)
  let json = task.to_json()
  // Task::to_json delegates to Stopped::to_json
  guard json
    is {
      "status": "stopped",
      "id": "223e4567-e89b-12d3-a456-426614174000",
      "cwd": "/tmp/stopped",
      "name": "stopped-task",
      ..
    } else {
    fail("Unexpected JSON structure")
  }
}

///|
test "Task::from_json for Running variant with idle status" {
  let json : Json = {
    "name": "running-task",
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "cwd": "/tmp/running",
    "port": 8080,
    "status": "idle",
    "created": 1000,
    "updated": 2000,
    "web_search": false,
    "queued_messages": [],
    "model": "gpt-4",
  }
  let task : Task = @json.from_json(json)
  guard task is Running(running) else { fail("Expected Running variant") }
  assert_true(running.name == Some("running-task"))
  assert_true(running.id == @uuid.parse("123e4567-e89b-12d3-a456-426614174000"))
  assert_true(running.cwd == "/tmp/running")
  assert_true(running.port == 8080)
  assert_true(running.status is Idle)
}

///|
test "Task::from_json for Running variant with generating status" {
  let json : Json = {
    "name": "generating-task",
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "cwd": "/tmp/generating",
    "port": 9090,
    "status": "generating",
    "created": 1000,
    "updated": 2000,
    "web_search": true,
    "queued_messages": [],
    "model": "gpt-4",
  }
  let task : Task = @json.from_json(json)
  guard task is Running(running) else { fail("Expected Running variant") }
  assert_true(running.name == Some("generating-task"))
  assert_true(running.status is Busy)
}

///|
test "Task::from_json for Stopped variant" {
  let json : Json = {
    "name": "stopped-task",
    "id": "223e4567-e89b-12d3-a456-426614174000",
    "cwd": "/tmp/stopped",
    "status": "stopped",
    "created": 1000,
    "updated": 2000,
    "web_search": true,
  }
  let task : Task = @json.from_json(json)
  guard task is Stopped(stopped) else { fail("Expected Stopped variant") }
  assert_true(stopped.name == Some("stopped-task"))
  assert_true(stopped.id == @uuid.parse("223e4567-e89b-12d3-a456-426614174000"))
  assert_true(stopped.cwd == "/tmp/stopped")
  assert_true(stopped.web_search == true)
}

///|
test "Task roundtrip: Running -> JSON -> Task" {
  let running = Running::{
    name: Some("roundtrip-running"),
    id: @uuid.parse("323e4567-e89b-12d3-a456-426614174000"),
    cwd: "/tmp/roundtrip",
    port: 7070,
    status: Idle,
    queued_messages: [],
    created: @clock.Timestamp::from_ms(5000),
    updated: @clock.Timestamp::from_ms(6000),
    web_search: true,
    model: "gpt-4",
    broadcast: @broadcast.Broadcast::new(),
  }
  let original = Task::Running(running)
  let json = original.to_json()
  let restored : Task = @json.from_json(json)
  guard restored is Running(restored_running) else {
    fail("Expected Running variant after roundtrip")
  }
  assert_true(restored_running.name == Some("roundtrip-running"))
  assert_true(
    restored_running.id == @uuid.parse("323e4567-e89b-12d3-a456-426614174000"),
  )
  assert_true(restored_running.cwd == "/tmp/roundtrip")
  assert_true(restored_running.port == 7070)
  assert_true(restored_running.web_search == true)
}

///|
test "Task roundtrip: Stopped -> JSON -> Task" {
  let stopped = Stopped::{
    name: Some("roundtrip-stopped"),
    id: @uuid.parse("423e4567-e89b-12d3-a456-426614174000"),
    cwd: "/tmp/roundtrip-stopped",
    created: @clock.Timestamp::from_ms(5000),
    updated: @clock.Timestamp::from_ms(6000),
    web_search: false,
    broadcast: @broadcast.Broadcast::new(),
  }
  let original = Task::Stopped(stopped)
  let json = original.to_json()
  let restored : Task = @json.from_json(json)
  guard restored is Stopped(restored_stopped) else {
    fail("Expected Stopped variant after roundtrip")
  }
  assert_true(restored_stopped.name == Some("roundtrip-stopped"))
  assert_true(
    restored_stopped.id == @uuid.parse("423e4567-e89b-12d3-a456-426614174000"),
  )
  assert_true(restored_stopped.cwd == "/tmp/roundtrip-stopped")
  assert_true(restored_stopped.web_search == false)
}

///|
test "Task::from_json with missing status field" {
  let json : Json = {
    "name": "no-status",
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "cwd": "/tmp/no-status",
  }
  let result : Result[Task, @json.JsonDecodeError] = Ok(@json.from_json(json)) catch {
    error => Err(error)
  }
  guard result is Err(_) else {
    fail("Expected JsonDecodeError for missing status field")
  }
}

///|
test "Task::from_json with unknown status" {
  let json : Json = {
    "name": "unknown-status",
    "id": "123e4567-e89b-12d3-a456-426614174000",
    "cwd": "/tmp/unknown",
    "status": "unknown",
    "created": 1000,
    "updated": 2000,
  }
  let result : Result[Task, @json.JsonDecodeError] = Ok(@json.from_json(json)) catch {
    error => Err(error)
  }
  guard result is Err(_) else {
    fail("Expected JsonDecodeError for unknown status")
  }
}
