///|
struct DefinitionsIndexFile {
  definitions : Array[JobDefinition]
  workflows : Array[WorkflowDefinition]
} derive(ToJson, FromJson, Show)

///|
struct RunsIndexFile {
  runs : Array[JobRun]
  steps : Array[JobStepRun]
} derive(ToJson, FromJson, Show)

///|
struct ArtifactsIndexFile {
  artifacts : Array[ArtifactRecord]
} derive(ToJson, FromJson, Show)

///|
struct ChatBindingsFile {
  bindings : Array[ChatBinding]
} derive(ToJson, FromJson, Show)

///|
struct NotificationPreferencesFile {
  preferences : Array[JobNotificationPreference]
} derive(ToJson, FromJson, Show)

///|
struct JobProposalsFile {
  proposals : Array[JobProposal]
} derive(ToJson, FromJson, Show)

///|
pub struct SystemStore {
  root : String
  definitions : Map[String, JobDefinition]
  workflows : Map[String, WorkflowDefinition]
  runs : Map[String, JobRun]
  steps : Map[String, JobStepRun]
  artifacts : Map[String, ArtifactRecord]
  chat_bindings : Map[String, ChatBinding]
  notification_preferences : Map[String, JobNotificationPreference]
  proposals : Map[String, JobProposal]
}

///|
pub fn SystemStore::new(root~ : String) -> SystemStore {
  SystemStore::{
    root,
    definitions: {},
    workflows: {},
    runs: {},
    steps: {},
    artifacts: {},
    chat_bindings: {},
    notification_preferences: {},
    proposals: {},
  }
}

///|
pub fn SystemStore::root_dir(self : SystemStore) -> String {
  self.root
}

///|
fn SystemStore::definitions_file(self : SystemStore) -> String {
  self.root |> @pathx.join("definitions.json")
}

///|
fn SystemStore::runs_index_file(self : SystemStore) -> String {
  self.root |> @pathx.join("index") |> @pathx.join("runs.json")
}

///|
fn SystemStore::artifacts_index_file(self : SystemStore) -> String {
  self.root |> @pathx.join("index") |> @pathx.join("artifacts.json")
}

///|
fn SystemStore::chat_bindings_file(self : SystemStore) -> String {
  self.root |> @pathx.join("chat_bindings.json")
}

///|
fn SystemStore::notification_preferences_file(self : SystemStore) -> String {
  self.root |> @pathx.join("notification_preferences.json")
}

///|
fn SystemStore::job_proposals_file(self : SystemStore) -> String {
  self.root |> @pathx.join("job_proposals.json")
}

///|
fn SystemStore::run_dir(self : SystemStore, run_id : String) -> String {
  self.root |> @pathx.join("runs") |> @pathx.join(run_id)
}

///|
fn SystemStore::run_meta_file(self : SystemStore, run_id : String) -> String {
  self.run_dir(run_id) |> @pathx.join("meta.json")
}

///|
fn SystemStore::step_dir(self : SystemStore, run_id : String) -> String {
  self.run_dir(run_id) |> @pathx.join("steps")
}

///|
fn SystemStore::step_meta_file(
  self : SystemStore,
  run_id : String,
  step_id : String,
) -> String {
  self.step_dir(run_id) |> @pathx.join("\{step_id}.json")
}

///|
pub fn SystemStore::run_events_file(
  self : SystemStore,
  run_id : String,
) -> String {
  self.run_dir(run_id) |> @pathx.join("events.jsonl")
}

///|
fn SystemStore::artifact_record_file(
  self : SystemStore,
  artifact_id : String,
) -> String {
  self.artifact_dir(artifact_id) |> @pathx.join("record.json")
}

///|
pub fn SystemStore::artifact_dir(
  self : SystemStore,
  artifact_id : String,
) -> String {
  self.root |> @pathx.join("artifacts") |> @pathx.join(artifact_id)
}

///|
pub fn SystemStore::artifact_content_file(
  self : SystemStore,
  artifact_id : String,
  file_name? : String = "content.bin",
) -> String {
  self.artifact_dir(artifact_id) |> @pathx.join(file_name)
}

///|
async fn SystemStore::ensure_directories(self : SystemStore) -> Unit {
  @fsx.make_directory(self.root, recursive=true) catch {
    _ => ()
  }
  @fsx.make_directory(self.root |> @pathx.join("runs"), recursive=true) catch {
    _ => ()
  }
  @fsx.make_directory(self.root |> @pathx.join("artifacts"), recursive=true) catch {
    _ => ()
  }
  @fsx.make_directory(self.root |> @pathx.join("index"), recursive=true) catch {
    _ => ()
  }
}

///|
fn[K : Hash + Eq, V] clear_map(map : Map[K, V]) -> Unit {
  let keys = map.keys().to_array()
  for key in keys {
    map.remove(key) |> ignore()
  }
}

///|
async fn[T : @json.FromJson] load_json_file(
  path : String,
  message : String,
) -> T {
  let content = @fsx.read_file(path)
  @json.from_json(@json.parse(content)) catch {
    error => fail("\{message}: \{error}")
  }
}

///|
pub async fn SystemStore::load(self : SystemStore) -> Unit {
  clear_map(self.definitions)
  clear_map(self.workflows)
  clear_map(self.runs)
  clear_map(self.steps)
  clear_map(self.artifacts)
  clear_map(self.chat_bindings)
  clear_map(self.notification_preferences)
  clear_map(self.proposals)

  if @fsx.exists(self.definitions_file()) {
    let file : DefinitionsIndexFile = load_json_file(
      self.definitions_file(),
      "Failed to load job definitions",
    )
    for definition in file.definitions {
      self.definitions.set(definition.id, definition)
    }
    for workflow in file.workflows {
      self.workflows.set(workflow.id, workflow)
    }
  }

  if @fsx.exists(self.runs_index_file()) {
    let file : RunsIndexFile = load_json_file(
      self.runs_index_file(),
      "Failed to load job runs index",
    )
    for run in file.runs {
      self.runs.set(run.id, run)
    }
    for step in file.steps {
      self.steps.set("\{step.run_id}:\{step.step_id}", step)
    }
  }

  if @fsx.exists(self.artifacts_index_file()) {
    let file : ArtifactsIndexFile = load_json_file(
      self.artifacts_index_file(),
      "Failed to load job artifacts index",
    )
    for artifact in file.artifacts {
      self.artifacts.set(artifact.id, artifact)
    }
  }

  if @fsx.exists(self.chat_bindings_file()) {
    let file : ChatBindingsFile = load_json_file(
      self.chat_bindings_file(),
      "Failed to load job chat bindings",
    )
    for binding in file.bindings {
      self.chat_bindings.set(binding.id, binding)
    }
  }

  if @fsx.exists(self.notification_preferences_file()) {
    let file : NotificationPreferencesFile = load_json_file(
      self.notification_preferences_file(),
      "Failed to load notification preferences",
    )
    for preference in file.preferences {
      self.notification_preferences.set(preference.id, preference)
    }
  }

  if @fsx.exists(self.job_proposals_file()) {
    let file : JobProposalsFile = load_json_file(
      self.job_proposals_file(),
      "Failed to load job proposals",
    )
    for proposal in file.proposals {
      self.proposals.set(proposal.id, proposal)
    }
  }
}

///|
async fn SystemStore::save_definitions_index(self : SystemStore) -> Unit {
  self.ensure_directories()
  let file = DefinitionsIndexFile::{
    definitions: self.definitions.values().to_array(),
    workflows: self.workflows.values().to_array(),
  }
  @fsx.write_to_file(self.definitions_file(), file.to_json().stringify())
}

///|
async fn SystemStore::save_runs_index(self : SystemStore) -> Unit {
  self.ensure_directories()
  let file = RunsIndexFile::{
    runs: self.runs.values().to_array(),
    steps: self.steps.values().to_array(),
  }
  @fsx.write_to_file(self.runs_index_file(), file.to_json().stringify())
}

///|
async fn SystemStore::save_artifacts_index(self : SystemStore) -> Unit {
  self.ensure_directories()
  let file = ArtifactsIndexFile::{
    artifacts: self.artifacts.values().to_array(),
  }
  @fsx.write_to_file(self.artifacts_index_file(), file.to_json().stringify())
}

///|
async fn SystemStore::save_chat_bindings(self : SystemStore) -> Unit {
  self.ensure_directories()
  let file = ChatBindingsFile::{
    bindings: self.chat_bindings.values().to_array(),
  }
  @fsx.write_to_file(self.chat_bindings_file(), file.to_json().stringify())
}

///|
async fn SystemStore::save_notification_preferences(self : SystemStore) -> Unit {
  self.ensure_directories()
  let file = NotificationPreferencesFile::{
    preferences: self.notification_preferences.values().to_array(),
  }
  @fsx.write_to_file(
    self.notification_preferences_file(),
    file.to_json().stringify(),
  )
}

///|
async fn SystemStore::save_job_proposals(self : SystemStore) -> Unit {
  self.ensure_directories()
  let file = JobProposalsFile::{ proposals: self.proposals.values().to_array() }
  @fsx.write_to_file(self.job_proposals_file(), file.to_json().stringify())
}

///|
pub async fn SystemStore::save_definition(
  self : SystemStore,
  definition : JobDefinition,
) -> Unit {
  self.definitions.set(definition.id, definition)
  self.save_definitions_index()
}

///|
pub async fn SystemStore::save_workflow(
  self : SystemStore,
  workflow : WorkflowDefinition,
) -> Unit {
  self.workflows.set(workflow.id, workflow)
  self.save_definitions_index()
}

///|
pub async fn SystemStore::save_run(self : SystemStore, run : JobRun) -> Unit {
  self.ensure_directories()
  self.runs.set(run.id, run)
  @fsx.make_directory(self.run_dir(run.id), recursive=true) catch {
    _ => ()
  }
  @fsx.make_directory(self.step_dir(run.id), recursive=true) catch {
    _ => ()
  }
  @fsx.write_to_file(self.run_meta_file(run.id), run.to_json().stringify())
  self.save_runs_index()
}

///|
pub async fn SystemStore::save_step_run(
  self : SystemStore,
  step : JobStepRun,
) -> Unit {
  self.ensure_directories()
  self.steps.set("\{step.run_id}:\{step.step_id}", step)
  @fsx.make_directory(self.step_dir(step.run_id), recursive=true) catch {
    _ => ()
  }
  @fsx.write_to_file(
    self.step_meta_file(step.run_id, step.step_id),
    step.to_json().stringify(),
  )
  self.save_runs_index()
}

///|
pub async fn SystemStore::save_artifact(
  self : SystemStore,
  artifact : ArtifactRecord,
) -> Unit {
  self.ensure_directories()
  self.artifacts.set(artifact.id, artifact)
  let artifact_dir = self.artifact_dir(artifact.id)
  @fsx.make_directory(artifact_dir, recursive=true) catch {
    _ => ()
  }
  @fsx.write_to_file(
    self.artifact_record_file(artifact.id),
    artifact.to_json().stringify(),
  )
  self.save_artifacts_index()
}

///|
pub async fn SystemStore::save_chat_binding(
  self : SystemStore,
  binding : ChatBinding,
) -> Unit {
  self.chat_bindings.set(binding.id, binding)
  self.save_chat_bindings()
}

///|
pub async fn SystemStore::save_notification_preference(
  self : SystemStore,
  preference : JobNotificationPreference,
) -> Unit {
  self.notification_preferences.set(preference.id, preference)
  self.save_notification_preferences()
}

///|
pub async fn SystemStore::save_job_proposal(
  self : SystemStore,
  proposal : JobProposal,
) -> Unit {
  self.proposals.set(proposal.id, proposal)
  self.save_job_proposals()
}

///|
pub async fn SystemStore::delete_artifact(
  self : SystemStore,
  artifact_id : String,
) -> Bool {
  let artifact = match self.artifacts.get(artifact_id) {
    Some(artifact) => artifact
    None => return false
  }
  self.artifacts.remove(artifact_id) |> ignore()
  if @fsx.exists(self.artifact_record_file(artifact_id)) {
    @fsx.remove(self.artifact_record_file(artifact_id))
  }
  if @fsx.exists(artifact.path) {
    @fsx.remove(artifact.path)
  }
  if @fsx.exists(self.artifact_dir(artifact_id)) {
    @fsx.remove(self.artifact_dir(artifact_id)) catch {
      _ => ()
    }
  }
  self.save_artifacts_index()
  true
}

///|
pub fn SystemStore::get_definition(
  self : SystemStore,
  id : String,
) -> JobDefinition? {
  self.definitions.get(id)
}

///|
pub fn SystemStore::get_workflow(
  self : SystemStore,
  id : String,
) -> WorkflowDefinition? {
  self.workflows.get(id)
}

///|
pub fn SystemStore::get_run(self : SystemStore, id : String) -> JobRun? {
  self.runs.get(id)
}

///|
pub fn SystemStore::get_step_run(
  self : SystemStore,
  run_id : String,
  step_id : String,
) -> JobStepRun? {
  self.steps.get("\{run_id}:\{step_id}")
}

///|
pub fn SystemStore::get_artifact(
  self : SystemStore,
  id : String,
) -> ArtifactRecord? {
  self.artifacts.get(id)
}

///|
pub fn SystemStore::get_chat_binding(
  self : SystemStore,
  id : String,
) -> ChatBinding? {
  self.chat_bindings.get(id)
}

///|
pub fn SystemStore::get_notification_preference(
  self : SystemStore,
  id : String,
) -> JobNotificationPreference? {
  self.notification_preferences.get(id)
}

///|
pub fn SystemStore::get_job_proposal(
  self : SystemStore,
  id : String,
) -> JobProposal? {
  self.proposals.get(id)
}

///|
pub fn SystemStore::find_job_proposal_by_message_id(
  self : SystemStore,
  message_id : String,
) -> JobProposal? {
  for proposal in self.proposals.values() {
    if proposal.presented_message_id == Some(message_id) {
      return Some(proposal)
    }
  }
  None
}

///|
pub fn SystemStore::list_definitions(
  self : SystemStore,
) -> Array[JobDefinition] {
  self.definitions.values().to_array()
}

///|
pub fn SystemStore::list_workflows(
  self : SystemStore,
) -> Array[WorkflowDefinition] {
  self.workflows.values().to_array()
}

///|
pub fn SystemStore::list_runs(self : SystemStore) -> Array[JobRun] {
  self.runs.values().to_array()
}

///|
pub fn SystemStore::list_step_runs(
  self : SystemStore,
  run_id : String,
) -> Array[JobStepRun] {
  self.steps.values().filter(fn(step) { step.run_id == run_id }).to_array()
}

///|
pub fn SystemStore::list_artifacts(
  self : SystemStore,
  run_id? : String,
) -> Array[ArtifactRecord] {
  match run_id {
    Some(run_id) =>
      self.artifacts
      .values()
      .filter(fn(artifact) { artifact.run_id == run_id })
      .to_array()
    None => self.artifacts.values().to_array()
  }
}

///|
pub fn SystemStore::list_chat_bindings(
  self : SystemStore,
) -> Array[ChatBinding] {
  self.chat_bindings.values().to_array()
}

///|
pub fn SystemStore::list_notification_preferences(
  self : SystemStore,
) -> Array[JobNotificationPreference] {
  self.notification_preferences.values().to_array()
}

///|
pub fn SystemStore::list_job_proposals(
  self : SystemStore,
) -> Array[JobProposal] {
  self.proposals.values().to_array()
}

///|
pub async fn SystemStore::append_run_event(
  self : SystemStore,
  event : JobRunEvent,
) -> Unit {
  self.ensure_directories()
  @fsx.make_directory(self.run_dir(event.run_id), recursive=true) catch {
    _ => ()
  }
  let path = self.run_events_file(event.run_id)
  let existing = if @fsx.exists(path) { @fsx.read_file(path) } else { "" }
  let line = event.to_json().stringify()
  let content = if existing.is_blank() { line } else { "\{existing}\n\{line}" }
  @fsx.write_to_file(path, content)
}

///|
pub async fn SystemStore::list_run_events(
  self : SystemStore,
  run_id : String,
) -> Array[JobRunEvent] {
  let path = self.run_events_file(run_id)
  guard @fsx.exists(path) else { return [] }
  let events : Array[JobRunEvent] = []
  for raw_line in @fsx.read_file(path).split("\n") {
    let line = raw_line.to_string().trim().to_string()
    if line.is_blank() {
      continue
    }
    let event : JobRunEvent = @json.from_json(@json.parse(line)) catch {
      error => fail("Failed to parse run event from \{path}: \{error}")
    }
    events.push(event)
  }
  events
}
