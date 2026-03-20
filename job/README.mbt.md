# Job Package

The job package provides background job management for long-running processes.

## Core Types

### `Job`

Represents a running or completed background job.

```moonbit nocheck
///|
pub struct Job {
  id : Id
  name : String
  description : String?
  command : String
  cwd : String
  stdout : String
  stderr : String
  // private: process
}
```

**Fields:**
- `id`: Unique job identifier
- `name`: Human-readable job name
- `command`: The shell command being executed
- `cwd`: Working directory
- `stdout`: Path to stdout log file
- `stderr`: Path to stderr log file

### `Id`

Unique identifier for jobs.

```moonbit nocheck
///|
pub(all) struct Id(Int) derive(Hash, Eq)
```

### `Manager`

Manages job lifecycle and tracks running jobs.

```moonbit nocheck
///|
pub struct Manager {
  cwd : String
  // private: id counter, process manager, jobs map
}
```

## Key APIs

### Manager Creation

```moonbit nocheck
pub fn Manager::new(cwd~ : String) -> Manager
```

### Spawning Jobs

```moonbit nocheck
pub async fn Manager::spawn(
  self : Manager,
  name~ : String,
  description? : String,
  command~ : String,
  cwd? : String,
) -> Job
```

### Job Operations

```moonbit nocheck
// Check job status
pub fn Job::status(self : Job) -> Int?

// Wait for job completion
pub async fn Job::wait(self : Job) -> Int

// Wait for specific job by ID
pub async fn Manager::wait(self : Manager, id : Id) -> Int

// Start the process manager
pub async fn Manager::start(self : Manager) -> Unit
```

### Job Listing

```moonbit nocheck
// List all jobs
pub fn Manager::list(self : Manager) -> Array[Job]

// Get specific job
pub fn Manager::get(self : Manager, id : Id) -> Job?
```

## Error Types

```moonbit nocheck
///|
pub suberror InvalidJobId {
  InvalidJobId(Id)
}
```

## Job Lifecycle

```
Manager::spawn()
    │
    ├─► Generate unique ID
    │
    ├─► Create job directory (.moonclaw/jobs/{id}/) for stdout/stderr capture
    │
    ├─► Create stdout/stderr files
    │
    ├─► Spawn process with @spawn.Manager
    │
    ▼
Job (running)
    │
    ├─► Job::status() → None (still running)
    │
    ├─► Job::wait() → blocks until complete
    │
    ▼
Job (completed)
    │
    └─► Job::status() → exit code
```

## Usage Example

```moonbit nocheck
// Create job manager
let job_manager = @job.Manager::new(cwd="/project")

// Start the manager
job_manager.start()

// Spawn a background job
let job = job_manager.spawn(
  name="Build Project",
  description="Run the build script",
  command="npm run build",
)

// Check status
match job.status() {
  None => println("Job is still running")
  Some(code) => println("Job completed with code \{code}")
}

// Wait for completion
let exit_code = job.wait()

// List all jobs
for job in job_manager.list() {
  println("\{job.name}: \{job.status()}")
}
```

## Job Storage

Jobs store their output in `.moonclaw/jobs/{id}/`:
- `stdout`: Standard output from the command
- `stderr`: Standard error from the command

This package-level storage is distinct from the higher-level workflow run workspace used by the newer job runtime. Operator-facing workflow runs now create visible workspaces under the configured workspace root, for example:

- `<workspace>/moonclaw-jobs/<run-id>`
- `<parent_run_workspace>/moonclaw-subjobs/<run-id>`

## Dependencies

- `spawn`: Process spawning
- `fsx`: File system operations
- `pathx`: Path utilities
