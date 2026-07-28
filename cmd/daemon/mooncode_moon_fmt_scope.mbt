///|
priv struct MoonCodeFmtPathState {
  tracked : Bool
  kind : String
  content : String?
  fingerprint : String
}

///|
priv struct MoonCodeFmtSnapshot {
  error : String
  states : Map[String, MoonCodeFmtPathState]
}

///|
priv struct MoonCodeFmtScopeOutcome {
  snapshot_error : String
  requested_paths : Array[String]
  changed_paths : Array[String]
  out_of_scope_paths : Array[String]
  restored_paths : Array[String]
  retained_paths : Array[String]
}

///|
async fn mooncode_moon_fmt_git(
  book_root : String,
  args : Array[String],
) -> Json {
  let process = @spawn.spawn("git", args.map(fn(arg) { arg }), cwd=book_root) catch {
    error =>
      return {
        "ok": false,
        "output": "",
        "message": "error running git: \{error}",
      }
  }
  {
    "ok": process.status == 0,
    "output": process.stdout,
    "message": (process.stdout + process.stderr).trim().to_owned(),
  }
}

///|
fn mooncode_moon_fmt_nul_paths(output : String) -> Array[String] {
  output
  .split("\u0000")
  .filter(fn(value) { value != "" })
  .map(fn(value) { value.to_owned() })
  .to_array()
}

///|
async fn mooncode_moon_fmt_path_state(
  book_root : String,
  path : String,
  tracked : Bool,
) -> MoonCodeFmtPathState {
  let absolute = @pathx.join(book_root, path)
  let kind = if !@moonclaw_fsx.exists(absolute) {
    "absent"
  } else {
    match @moonclaw_fsx.kind(absolute) {
      @moonclaw_fsx.Regular => "regular"
      @moonclaw_fsx.SymLink => "symlink"
      _ => "unsupported"
    }
  }
  let content = if kind == "regular" {
    Some(@moonclaw_fsx.read_file(absolute))
  } else {
    None
  }
  let fingerprint = if tracked {
    let result = mooncode_moon_fmt_git(book_root, [
      "diff", "--binary", "--no-ext-diff", "HEAD", "--", path,
    ])
    if !mooncode_json_bool(result, "ok", default=false) {
      raise Failure::Failure(
        mooncode_json_string(
          result,
          "message",
          default="could not fingerprint tracked path \{path}",
        ),
      )
    }
    mooncode_json_string(result, "output", default="")
  } else if kind == "symlink" {
    @moonclaw_fsx.readlink(absolute)
  } else {
    ""
  }
  { tracked, kind, content, fingerprint }
}

///|
async fn mooncode_moon_fmt_snapshot(book_root : String) -> MoonCodeFmtSnapshot {
  let tracked = mooncode_moon_fmt_git(book_root, [
    "diff", "--name-only", "-z", "--relative", "HEAD", "--", ".",
  ])
  let untracked = mooncode_moon_fmt_git(book_root, [
    "ls-files", "--others", "--exclude-standard", "-z", "--", ".",
  ])
  for result in [tracked, untracked] {
    if !mooncode_json_bool(result, "ok", default=false) {
      return {
        error: mooncode_json_string(
          result,
          "message",
          default="Git working-tree snapshot failed",
        ),
        states: {},
      }
    }
  }
  let states : Map[String, MoonCodeFmtPathState] = {}
  for entry in [(tracked, true), (untracked, false)] {
    for
      path in mooncode_moon_fmt_nul_paths(
        mooncode_json_string(entry.0, "output", default=""),
      ) {
      if !states.contains(path) {
        states[path] = mooncode_moon_fmt_path_state(book_root, path, entry.1) catch {
          error =>
            return { error: "could not snapshot \{path}: \{error}", states: {} }
        }
      }
    }
  }
  { error: "", states }
}

///|
fn mooncode_moon_fmt_same_state(
  before : MoonCodeFmtPathState?,
  after : MoonCodeFmtPathState?,
) -> Bool {
  match (before, after) {
    (None, None) => true
    (Some(left), Some(right)) =>
      left.tracked == right.tracked &&
      left.kind == right.kind &&
      left.content == right.content &&
      left.fingerprint == right.fingerprint
    _ => false
  }
}

///|
fn mooncode_moon_fmt_changed_paths(
  before : MoonCodeFmtSnapshot,
  after : MoonCodeFmtSnapshot,
) -> Array[String] {
  let all : Map[String, Bool] = {}
  for path, _ in before.states.iter2() {
    all[path] = true
  }
  for path, _ in after.states.iter2() {
    all[path] = true
  }
  let changed : Array[String] = []
  for path, _ in all.iter2() {
    if !mooncode_moon_fmt_same_state(
        before.states.get(path),
        after.states.get(path),
      ) {
      changed.push(path)
    }
  }
  changed.sort_by(fn(left, right) { left.compare(right) })
  changed
}

///|
fn mooncode_moon_fmt_path_is_requested(
  book_root : String,
  selector_root : String,
  requested_paths : Array[String],
  changed_path : String,
) -> Bool {
  let absolute = @pathx.normalize(@pathx.join(book_root, changed_path))
  for path in requested_paths {
    let resolved = mooncode_resolve_book_path(selector_root, path)
    let requested = mooncode_json_string(resolved, "absolute_path", default="")
    if requested != "" &&
      (absolute == requested || absolute.has_prefix(requested + "/")) {
      return true
    }
  }
  false
}

///|
async fn mooncode_moon_fmt_restore_path(
  book_root : String,
  path : String,
  before : MoonCodeFmtPathState?,
  after : MoonCodeFmtPathState?,
) -> Unit {
  match before {
    Some({ kind: "regular", content: Some(content), .. }) =>
      @moonclaw_fsx.write_to_file(@pathx.join(book_root, path), content)
    Some({ kind: "absent", .. }) =>
      if @moonclaw_fsx.exists(@pathx.join(book_root, path)) {
        @moonclaw_fsx.remove(@pathx.join(book_root, path))
      }
    Some(_) => ()
    None =>
      match after {
        Some({ tracked: true, .. }) =>
          ignore(
            mooncode_moon_fmt_git(book_root, [
              "restore", "--worktree", "--", path,
            ]),
          )
        Some(_) =>
          if @moonclaw_fsx.exists(@pathx.join(book_root, path)) {
            @moonclaw_fsx.remove(@pathx.join(book_root, path))
          }
        None => ()
      }
  }
}

///|
async fn mooncode_moon_fmt_verify_and_restore(
  book_root : String,
  selector_root : String,
  requested_paths : Array[String],
  before : MoonCodeFmtSnapshot,
) -> MoonCodeFmtScopeOutcome {
  let after = mooncode_moon_fmt_snapshot(book_root)
  if after.error != "" {
    return {
      snapshot_error: after.error,
      requested_paths,
      changed_paths: [],
      out_of_scope_paths: [],
      restored_paths: [],
      retained_paths: [],
    }
  }
  let changed_paths = mooncode_moon_fmt_changed_paths(before, after)
  let out_of_scope_paths = changed_paths.filter(fn(path) {
    !mooncode_moon_fmt_path_is_requested(
      book_root, selector_root, requested_paths, path,
    )
  })
  for path in out_of_scope_paths {
    try
      mooncode_moon_fmt_restore_path(
        book_root,
        path,
        before.states.get(path),
        after.states.get(path),
      )
    catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
  let restored_paths : Array[String] = []
  let retained_paths : Array[String] = []
  let restored = if out_of_scope_paths.is_empty() {
    MoonCodeFmtSnapshot::{ error: "", states: {} }
  } else {
    mooncode_moon_fmt_snapshot(book_root)
  }
  if restored.error != "" {
    for path in out_of_scope_paths {
      retained_paths.push(path)
    }
  } else {
    for path in out_of_scope_paths {
      if mooncode_moon_fmt_same_state(
          before.states.get(path),
          restored.states.get(path),
        ) {
        restored_paths.push(path)
      } else {
        retained_paths.push(path)
      }
    }
  }
  {
    snapshot_error: restored.error,
    requested_paths,
    changed_paths,
    out_of_scope_paths,
    restored_paths,
    retained_paths,
  }
}

///|
fn MoonCodeFmtScopeOutcome::to_json(self : MoonCodeFmtScopeOutcome) -> Json {
  {
    "requested_paths": self.requested_paths,
    "changed_paths": self.changed_paths,
    "out_of_scope_paths": self.out_of_scope_paths,
    "restored_paths": self.restored_paths,
    "retained_paths": self.retained_paths,
    "restore_verified": self.snapshot_error == "" &&
    self.retained_paths.is_empty(),
    "snapshot_error": self.snapshot_error,
  }
}
