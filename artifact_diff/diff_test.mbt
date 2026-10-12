///|
test "line comparison identifies edits and exact positions" {
  let diff = @artifact_diff.compare_text(
    "one\ntwo\nthree\n", "one\nTWO\nthree\nfour",
  )
  assert_false(diff.identical)
  inspect(diff.added_lines, content="2")
  inspect(diff.removed_lines, content="1")
  inspect(diff.unchanged_lines, content="2")
  inspect(
    diff.edits.map(e => e.kind),
    content="[equal, delete, insert, equal, insert]",
  )
  inspect(diff.edits[1].left_line, content="Some(2)")
  inspect(diff.edits[2].right_line, content="Some(2)")
  inspect(diff.edits[4].ending, content="")
}

///|
test "empty and newline only contents retain exact lines" {
  let empty = @artifact_diff.compare_text("", "")
  assert_true(empty.identical)
  inspect(empty.left_lines, content="0")
  inspect(empty.edits.length(), content="0")
  let added = @artifact_diff.compare_text("", "\n\n")
  inspect(added.added_lines, content="2")
  inspect(added.edits[0].text, content="")
  inspect(@artifact_diff.compare_text("a", "").removed_lines, content="1")
}

///|
test "line endings final newline and whitespace are meaningful" {
  let diff = @artifact_diff.compare_text("a\r\nb\nlast", "a\nb\nlast\n")
  inspect(diff.unchanged_lines, content="1")
  inspect(diff.removed_lines, content="2")
  inspect(diff.added_lines, content="2")
  inspect(diff.edits[0].ending.to_json().stringify(), content="\"\\r\\n\"")
  assert_false(@artifact_diff.compare_text(" a\n", "a\n").identical)
  assert_false(@artifact_diff.compare_text("a\t\n", "a \n").identical)
  inspect(
    @artifact_diff.compare_text("x\ry", "x\ry").edits[0].text
    .to_json()
    .stringify(),
    content="\"x\\ry\"",
  )
}

///|
test "unicode including astral characters is preserved" {
  let diff = @artifact_diff.compare_text(
    "你好 🌙\nold\n", "你好 🌙\n新内容\n",
  )
  inspect(diff.unchanged_lines, content="1")
  inspect(diff.edits[0].text, content="你好 🌙")
  inspect(diff.edits[2].text, content="新内容")
}

///|
test "repeated line alignment has deterministic deletion first ties" {
  let diff = @artifact_diff.compare_text("a\nb\na\n", "b\na\nb\n")
  inspect(diff.edits.map(e => e.kind), content="[delete, equal, equal, insert]")
  inspect(diff.unchanged_lines, content="2")
  assert_eq(
    diff.to_json(),
    @artifact_diff.compare_text("a\nb\na\n", "b\na\nb\n").to_json(),
  )
}

///|
test "bounded diff reconstructs both inputs across exhaustive small fixtures" {
  let samples = [""]
  for length = 1; length <= 4; length = length + 1 {
    for mask = 0; mask < 1 << length; mask = mask + 1 {
      let text = StringBuilder::new()
      for i = 0; i < length; i = i + 1 {
        text.write_string(if (mask & (1 << i)) == 0 { "a\n" } else { "b\n" })
      }
      samples.push(text.to_string())
    }
  }
  for left in samples {
    for right in samples {
      let diff = @artifact_diff.compare_text(left, right)
      let before = StringBuilder::new()
      let after = StringBuilder::new()
      let mut left_line = 1
      let mut right_line = 1
      for edit in diff.edits {
        if edit.kind != "insert" {
          assert_eq(edit.left_line, Some(left_line))
          left_line += 1
          before.write_string(edit.text + edit.ending)
        } else {
          assert_true(edit.left_line is None)
        }
        if edit.kind != "delete" {
          assert_eq(edit.right_line, Some(right_line))
          right_line += 1
          after.write_string(edit.text + edit.ending)
        } else {
          assert_true(edit.right_line is None)
        }
      }
      assert_eq(before.to_string(), left)
      assert_eq(after.to_string(), right)
      assert_eq(diff.identical, left == right)
      assert_eq(diff.left_lines, diff.unchanged_lines + diff.removed_lines)
      assert_eq(diff.right_lines, diff.unchanged_lines + diff.added_lines)
    }
  }
}

///|
test "maximum line count and text size pass while overflow and binary fail" {
  let text = "a\n".repeat(2000)
  inspect(
    @artifact_diff.compare_text(text, text).unchanged_lines,
    content="2000",
  )
  inspect(
    @artifact_diff.compare_text("x".repeat(1048576), "").removed_lines,
    content="1",
  )
  assert_true((try? @artifact_diff.compare_text(text + "a\n", "")) is Err(_))
  assert_true(
    (try? @artifact_diff.compare_text("", "x".repeat(1048577))) is Err(_),
  )
  assert_true((try? @artifact_diff.compare_text("a\u0000b", "")) is Err(_))
}
