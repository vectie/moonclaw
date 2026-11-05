///|
/// A disposable view of observed calls and their explicit references. Selection
/// edges do not assert data dependencies between calls or successive rounds.
fn mooncode_conversation_work_graph(
  command_id : String,
  steps : Array[Json],
) -> Json {
  let nodes : Array[Json] = []
  let edges : Array[Json] = []
  let batches : Map[Int32, Bool] = Map([])
  let results : Map[String, String] = Map([])
  for step in steps {
    let tool = mooncode_json_string(step, "tool", default="")
    let round = mooncode_json_int(step, "planner_step", default=0)
    if tool == "" || round == 0 {
      continue
    }
    let batch_id = "\{command_id}:round:\{round}"
    if !batches.contains(round) {
      batches[round] = true
      nodes.push({ "id": batch_id, "kind": "batch", "step": round })
    }
    let id = mooncode_json_string(step, "item_id", default="")
    let reference = mooncode_json_string(step, "evidence_ref", default="")
    nodes.push({
      "id": id,
      "kind": "operation",
      "batch_id": batch_id,
      "tool": tool,
      "status": mooncode_json_string(step, "status", default=""),
      "evidence_ref": reference,
    })
    edges.push({ "from": batch_id, "to": id, "kind": "selects" })
    if reference != "" {
      results[reference] = id
    }
    let paths = mooncode_json_array_string_items(step, "changed_paths")
    let sandbox = mooncode_json_object_field_or_empty(
      mooncode_json_object_field_or_empty(step, "evidence"),
      "sandbox_evidence",
    )
    for field in ["changed_paths", "artifacts"] {
      for path in mooncode_json_array_string_items(sandbox, field) {
        if !paths.contains(path) {
          paths.push(path)
        }
      }
    }
    let path = mooncode_json_string(step, "path", default="")
    if path != "" && tool != "read_skill" && !paths.contains(path) {
      paths.push(path)
    }
    for index, path in paths {
      let resource_id = "\{id}:file:\{index}"
      nodes.push({
        "id": resource_id,
        "kind": "resource",
        "operation_id": id,
        "path": path,
        "fingerprint": "",
      })
      edges.push({ "from": id, "to": resource_id, "kind": "resource" })
    }
    for index, input in mooncode_json_array_items(step, "inputs") {
      let resource_id = "\{id}:input:\{index}"
      nodes.push({
        "id": resource_id,
        "kind": "resource",
        "operation_id": id,
        "path": mooncode_json_string(input, "path", default=""),
        "fingerprint": mooncode_json_string(input, "fingerprint", default=""),
      })
      edges.push({ "from": resource_id, "to": id, "kind": "checks" })
    }
  }
  for step in steps {
    let reference = mooncode_json_string(step, "recalls", default="")
    if results.get(reference) is Some(source) {
      edges.push({
        "from": source,
        "to": mooncode_json_string(step, "item_id", default=""),
        "kind": "recalls",
      })
    }
  }
  { "nodes": nodes, "edges": edges }
}
