///|
test "editor handles wide unicode cursor movement and deletion" {
  let editor = Editor::new()
  ignore(editor.handle_key(Char('你')))
  ignore(editor.handle_key(Char('好')))
  ignore(editor.handle_key(Left))
  ignore(editor.handle_key(Backspace))
  inspect(editor.text(), content="好")
}

///|
test "editor history is reachable with arrow keys" {
  let editor = Editor::new()
  editor.set_text("first")
  ignore(editor.handle_key(Enter))
  editor.set_text("second")
  ignore(editor.handle_key(Enter))
  ignore(editor.handle_key(Up))
  inspect(editor.text(), content="second")
  ignore(editor.handle_key(Up))
  inspect(editor.text(), content="first")
  ignore(editor.handle_key(Down))
  inspect(editor.text(), content="second")
  ignore(editor.handle_key(Down))
  inspect(editor.text(), content="")
}

///|
test "parse_key decodes utf8 printable characters" {
  let bytes = @encoding/utf8.encode("你")
  inspect(key_to_string(parse_key(bytes[:])), content="你")
}
