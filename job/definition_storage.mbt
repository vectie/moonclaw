///|
/// Refresh only the definition index while holding the existing store lock.
/// Every writer merges its one definition/workflow into the latest durable map.
async fn SystemStore::reload_definitions_unlocked(self : SystemStore) -> Unit {
  clear_map(self.definitions)
  clear_map(self.workflows)
  if !@fsx.exists(self.definitions_file()) {
    return
  }
  let file : DefinitionsIndexFile = load_json_file(
    self.definitions_file(),
    "Failed to load job definitions",
  )
  for definition in file.definitions {
    self.definitions[definition.id] = definition
  }
  for workflow in file.workflows {
    self.workflows[workflow.id] = workflow
  }
}
