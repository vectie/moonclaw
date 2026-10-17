///|
/// A line edit with one-based positions. Ending is exactly LF, CRLF, or empty.
/// Text excludes that ending; a bare CR remains part of text.
pub struct LineEdit {
  kind : String
  left_line : Int32?
  right_line : Int32?
  text : String
  ending : String
} derive(ToJson)

///|
pub struct TextDiff {
  identical : Bool
  left_lines : Int32
  right_lines : Int32
  added_lines : Int32
  removed_lines : Int32
  unchanged_lines : Int32
  edits : Array[LineEdit]
} derive(ToJson)

///|
fn split_lines(text : String) -> Array[String] raise {
  guard text.length() <= 1048576 else { fail("Text exceeds 1 Mi code units") }
  guard !text.contains("\u0000") else {
    fail("NUL-containing content is not text")
  }
  let lines : Array[String] = []
  let pieces = text.split("\n").to_array()
  for index, piece in pieces {
    let terminated = index < pieces.length() - 1
    if terminated || !piece.is_empty() {
      lines.push(piece.to_owned() + (if terminated { "\n" } else { "" }))
      guard lines.length() <= 2000 else { fail("Text exceeds 2000 lines") }
    }
  }
  lines
}

///|
fn line_edit(
  kind : String,
  left_line : Int32?,
  right_line : Int32?,
  raw : String,
) -> LineEdit {
  let ending = if raw.has_suffix("\r\n") {
    "\r\n"
  } else if raw.has_suffix("\n") {
    "\n"
  } else {
    ""
  }
  {
    kind,
    left_line,
    right_line,
    text: raw[:raw.length() - ending.length()].to_owned(),
    ending,
  }
}

///|
/// Exact line comparison, including line endings and final-newline changes.
/// The minimal insert/delete script uses longest-common-subsequence alignment;
/// ties choose deletion first. No normalization or whitespace folding occurs.
pub fn compare_text(left : String, right : String) -> TextDiff raise {
  let before = split_lines(left)
  let after = split_lines(right)
  let dictionary : Map[String, Int32] = Map::new()
  let intern = fn(lines : Array[String]) {
    lines.map(fn(line) {
      match dictionary.get(line) {
        Some(id) => id
        None => {
          let id = dictionary.length()
          dictionary[line] = id
          id
        }
      }
    })
  }
  let a = intern(before)
  let b = intern(after)
  let width = b.length() + 1
  let lengths = FixedArray::make((a.length() + 1) * width, 0)
  for i = a.length() - 1; i >= 0; i = i - 1 {
    for j = b.length() - 1; j >= 0; j = j - 1 {
      lengths[i * width + j] = if a[i] == b[j] {
        lengths[(i + 1) * width + j + 1] + 1
      } else {
        let remove = lengths[(i + 1) * width + j]
        let add = lengths[i * width + j + 1]
        if remove >= add {
          remove
        } else {
          add
        }
      }
    }
  }
  let edits : Array[LineEdit] = []
  let mut removed = 0
  let mut added = 0
  let mut unchanged = 0
  for i = 0, j = 0; i < a.length() || j < b.length(); {
    if i < a.length() && j < b.length() && a[i] == b[j] {
      edits.push(line_edit("equal", Some(i + 1), Some(j + 1), before[i]))
      unchanged += 1
      continue i + 1, j + 1
    }
    if i < a.length() &&
      (
        j == b.length() ||
        lengths[(i + 1) * width + j] >= lengths[i * width + j + 1]
      ) {
      edits.push(line_edit("delete", Some(i + 1), None, before[i]))
      removed += 1
      continue i + 1, j
    }
    edits.push(line_edit("insert", None, Some(j + 1), after[j]))
    added += 1
    continue i, j + 1
  }
  {
    identical: left == right,
    left_lines: a.length(),
    right_lines: b.length(),
    added_lines: added,
    removed_lines: removed,
    unchanged_lines: unchanged,
    edits,
  }
}
