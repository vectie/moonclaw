///|
/// Holds a list of tasks that shares the same working directory (cwd).
///
/// This is necessary because we might have 1 running task and potentially have
/// many stopped tasks that shares the same cwd. This struct helps to group them
/// together and enforcing the invariant that at most 1 running task exists in
/// the list.
priv struct TaskLock {
  /// Mutex to synchronize spawning of new tasks.
  ///
  /// Life cycle:
  ///
  /// 1. Acquire `spawn_mutex` before inspecting or replacing the cwd owner.
  /// 2. New task creation retires the old child only if it is idle.
  /// 3. Spawn the task process and register it in `running`.
  /// 4. Hand off any initial message before releasing `spawn_mutex`.
  ///
  /// FIXME: this should be refactored into `Mutex[T]` for safer access
  spawn_mutex : @semaphore.Semaphore
  mut running : Running?
}

///|
fn TaskLock::new() -> TaskLock {
  { spawn_mutex: Semaphore(1), running: None, }
}
