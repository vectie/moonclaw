///|
// The fail-closed job facade remains a public result type while MoonFort owns
// process creation, so this package intentionally does not construct it.
#warnings("-struct_never_constructed")
pub struct Job {
  id : Id
  name : String
  description : String?
  command : String
  cwd : String
  stdout : String
  stderr : String
  priv exit_status : Int?
}

///|
pub fn Job::status(self : Job) -> Int? {
  self.exit_status
}

///|
#warnings("-unused_async")
pub async fn Job::wait(self : Job) -> Int {
  match self.exit_status {
    Some(status) => status
    None => raise ExecutionSandboxRequired(self.command)
  }
}

///|
pub impl ToJson for Job with fn to_json(self : Job) -> Json {
  let json : Map[String, Json] = {
    "id": self.id.0,
    "name": self.name,
    "command": self.command,
    "cwd": self.cwd,
    "stdout": self.stdout,
    "stderr": self.stderr,
  }
  if self.description is Some(desc) {
    json["description"] = desc.to_json()
  }
  Json::object(json)
}

///|
pub struct Manager {
  cwd : String
  priv jobs : Map[Id, Job]
}

///|
pub(all) struct Id(Int) derive(Hash, Eq)

///|
pub impl Show for Id with fn output(self : Id, logger : &Logger) -> Unit {
  Show::output(self.0, logger)
}

///|
pub impl ToJson for Id with fn to_json(self : Id) -> Json {
  self.0.to_json()
}

///|
pub impl @json.FromJson for Id with fn from_json(
  json : Json,
  json_path : @json.JsonPath,
) -> Id {
  let value : Int = @json.FromJson::from_json(json, json_path)
  Id(value)
}

///|
pub fn Manager::new(cwd~ : String, home? : String) -> Manager {
  ignore(home)
  { cwd, jobs: {} }
}

///|
pub suberror CommandApprovalRequired {
  CommandApprovalRequired(@security.CommandAssessment)
}

///|
pub suberror CommandBlocked {
  CommandBlocked(@security.CommandAssessment)
}

///|
/// Background host processes are disabled until the MoonFort executor exposes
/// a durable asynchronous-job lifecycle. Static command assessment is not an
/// execution boundary and must never authorize a host shell.
pub suberror ExecutionSandboxRequired {
  ExecutionSandboxRequired(String)
}

///|
#warnings("-unused_async")
pub async fn Manager::spawn(
  self : Manager,
  name~ : String,
  description? : String,
  command~ : String,
  cwd? : String,
) -> Job {
  let cwd = match cwd {
    Some(cwd) => cwd
    None => self.cwd
  }
  let assessment = @security.assess_shell_command(command, cwd, Some(self.cwd))
  if !assessment.allowed_by_policy {
    raise CommandBlocked(assessment)
  }
  if assessment.requires_approval {
    raise CommandApprovalRequired(assessment)
  }
  // Deliberately do not create output files or a job record. A caller must
  // obtain a MoonFort execution grant and use the sandbox executor instead.
  ignore(name)
  ignore(description)
  ignore(cwd)
  raise ExecutionSandboxRequired(command)
}

///|
pub suberror InvalidJobId {
  InvalidJobId(Id)
}

///|
pub async fn Manager::wait(self : Manager, id : Id) -> Int {
  guard self.jobs.get(id) is Some(job) else { raise InvalidJobId(id) }
  job.wait()
}

///|
#warnings("-unused_async")
pub async fn Manager::start(self : Manager) -> Unit {
  // Retained for source compatibility with list_jobs/wait_job wiring. There is
  // no host-process manager to start.
  ignore(self)
}

///|
pub fn Manager::list(self : Manager) -> Array[Job] {
  self.jobs.values().to_array()
}

///|
pub fn Manager::get(self : Manager, id : Id) -> Job? {
  self.jobs.get(id)
}
