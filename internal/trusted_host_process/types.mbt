///|
/// A deliberately closed set of Git operations used by MoonClaw's own
/// bookkeeping. There is no escape hatch for a caller-supplied executable,
/// argument vector, environment, or shell command.
pub(all) enum GitOperation {
  Init
  CheckIgnore(Array[String])
  ListFiles
  AddFiles(Array[String])
  AddAll
  Commit(String)
  StatusPorcelain
  StatusProductPorcelain
  StatusShort
  RecentLog(Int)
  RevListCount
  Head
  HeadTree
  CurrentBranch
  ListHeadTree
  CommitSubject
  DiffCheck
  DiffNamesBetween(base~ : String, target~ : String)
  DiffTree(String)
  AddProductAll
  RestoreHeadFiles(Array[String])
  DiffNoIndex(original~ : String, modified~ : String)
  WorktreeList
  WorktreeAdd(
    path~ : String,
    branch~ : String?,
    commit~ : String?,
    force_new_branch~ : Bool
  )
  WorktreeRemove(path~ : String, force~ : Bool)
  FmtTrackedPaths
  FmtUntrackedPaths
  FmtPathDiff(String)
  FmtRestorePath(String)
} derive(Debug)

///|
pub struct GitResult {
  status : Int
  stdout : String
  stderr : String
  elapsed : Int
}

///|
pub fn GitResult::status(self : GitResult) -> Int {
  self.status
}

///|
pub fn GitResult::stdout(self : GitResult) -> String {
  self.stdout
}

///|
pub fn GitResult::stderr(self : GitResult) -> String {
  self.stderr
}

///|
pub fn GitResult::elapsed(self : GitResult) -> Int {
  self.elapsed
}

///|
pub suberror TrustedHostProcessError {
  InvalidWorkspace(String)
  InvalidParameter(String)
  UnsafeRepositoryConfig(String)
  HostToolUnavailable(String)
} derive(Debug)
