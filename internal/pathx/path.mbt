///|
using @xpath {type Path}

///|
fn StringView::end_offset(self : StringView) -> Int {
  self.start_offset() + self.length()
}

///|
/// Path component separator
pub let sep : Char = '/'

///|
/// Return the directory name of path.
/// 
/// This behavior is similar to Python `os.path.dirname`, but inconsistent with Posix convention dirname command.
/// 
/// edge cases: when path is relative path without directory component, return "."
pub fn dirname(path : StringView) -> StringView {
  let dir = @xpath.Path::dirname(path.to_owned()).to_string()
  if dir.is_empty() {
    "."
  } else {
    dir
  }
}

///|
/// Return the basename of path 
/// 
/// 1. first trim trailing `/` if not root `/`
/// 2. extract last component after last `/`
/// 
/// This behavior is consistent with Posix convention basename command, but inconsistent with Python `os.path.basename`
/// 
pub fn basename(path : StringView) -> StringView {
  let path = match path {
    [.. path, '/'] => path
    path => path
  }
  for view = path.view() {
    match view {
      [] => break path
      [.., '/'] as view => break path.view(start_offset=view.end_offset())
      [.. view, _] => continue view
    }
  }
}

///|
/// Extract extension name include `.`
/// 
/// property: `stem(path) + ext(path) == basename(path)`
pub fn ext(path : StringView) -> StringView {
  Path::extname(path.to_owned())
}

///|
/// replace extension name with `ext`, if basename exists.
/// 
/// failed cases: 
///   1. if `basename(path)` is empty, return original path. 
///   2. if `basename(path)` is `.` or `..`, return original path.
/// 
/// This API is not consistent with Python `pathlib.Path.with_suffix`, which would raise exception in failed cases.
/// 
/// Justification:
/// 
/// when `replace_ext` fails, returning original path is logging friendly behavior,
/// by the way if `replace_ext` fails, user also hasn't good way to handle this error case.
/// 
/// for other purpose, if return original path LLM can re-try to diagnostic the issue.
/// 
pub fn replace_ext(path : StringView, ext : StringView) -> String {
  let basename = basename(path)
  match basename {
    "" => return path.to_owned()
    "." => return path.to_owned()
    ".." => return path.to_owned()
    _ => {
      let old_ext_len = match basename.rev_find(".") {
        None => 0
        Some(idx) => basename.length() - idx
      }
      let directory_stem = path.view(
        start_offset=0,
        end_offset=path.length() - old_ext_len,
      )
      let buffer = StringBuilder::new(
        size_hint=(directory_stem.length() + ext.length()) << 1,
      )
      buffer.write_stringview(directory_stem)
      buffer.write_stringview(ext)
      buffer.to_string()
    }
  }
}

///|
/// Extract stem part exclude `.`
/// 
/// property: `stem(path) + ext(path) == basename(path)`
pub fn stem(path : StringView) -> StringView {
  let base = basename(path)
  let ext = ext(path)
  base.view(start_offset=0, end_offset=base.length() - ext.length())
}

///|
priv enum SplitState {
  Root
  Segment
}

///|
fn skip_redundant_slashes(view : StringView) -> StringView {
  for rest = view {
    match rest {
      ['/', .. rest] => continue rest
      rest => break rest
    }
  }
}

///|
/// Split each path component, handle redundant slashes but doesn't resolve `.` and `..`.
pub fn split(view : StringView) -> Iter[StringView] {
  let mut state : SplitState = Root
  let mut last = view
  Iter::new(() => {
    for current = state {
      match current {
        Root =>
          match view {
            // More than 3 slashes are treated as single slash.
            [.. "///", .. rest] => {
              state = Segment
              last = skip_redundant_slashes(rest)
              break Some("/")
            }
            [.. "//", .. rest] => {
              state = Segment
              last = rest
              break Some("//")
            }
            ['/', .. rest] => {
              state = Segment
              last = rest
              break Some("/")
            }
            rest => {
              state = Segment
              last = rest
              continue Segment
            }
          }
        Segment =>
          break for rest = last.view() {
            match rest {
              ['/', .. rest] as view => {
                // Slice out the part before slash.
                let part = last
                  .data()
                  .view(
                    start_offset=last.start_offset(),
                    end_offset=view.start_offset(),
                  )
                last = skip_redundant_slashes(rest)
                break Some(part)
              }
              [_, .. rest] => continue rest
              [] as view =>
                if last.is_empty() {
                  break None
                } else {
                  let part = last
                  last = view
                  break Some(part)
                }
            }
          }
      }
    }
  })
}

///|
/// Normalize path by resolving `.` and `..` and eliminating redundant slashes.
pub fn normalize(view : StringView) -> String {
  Path::normalize(view.to_owned()).0
}

///|
/// 1. normalize path.
/// 2. if rhs is absolute path, return rhs.
pub fn join(p : StringView, q : StringView) -> String {
  Path::join(p.to_owned(), q.to_owned()).normalize().0
}

///|
pub fn is_absolute(path : StringView) -> Bool {
  Path::is_absolute(path.to_owned())
}

///|
pub fn is_relative(path : StringView) -> Bool {
  !is_absolute(path)
}

///|
/// Return relative path from `from` to `to`, `from` treated as current working directory.
///
/// property: `join(from, relative(from, to)) == resolve(to)`
/// 
/// join already normalizes the path, so no need to normalize here.
/// 
/// edge cases: when from is equal to to, return "."
pub fn relative(from : StringView, to : StringView) -> String raise {
  let result = Path::relative(to.to_owned(), base=from.to_owned()).0
  if result.is_empty() {
    "."
  } else {
    result
  }
}

///|
/// Resolve relative path to absolute path.
/// 
/// 1. if absolute path is given, normalize and return it.
/// 2. if relative path is given, join it with current working directory,
pub fn resolve(view : StringView) -> String raise {
  Path::resolve(view.to_owned()).0
}
