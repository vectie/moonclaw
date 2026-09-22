///|
test "word boundaries scan byte runs without removed byte lexmatch" {
  assert_eq(word_size_left(b"", 0), 0)
  assert_eq(word_size_left(b"one two  ", 9), 5)
  assert_eq(word_size_left(b"one two", 3), 3)
  assert_eq(word_size_left(b"one...  ", 8), 5)
  assert_eq(word_size_left(b"   ", 3), 3)
  assert_eq(word_right_left(b"one two", 0), 4)
  assert_eq(word_right_left(b"one two", 4), 3)
  assert_eq(word_right_left(b"one two", 7), 0)
  assert_eq(word_right_left(b"...  one", 0), 5)
  assert_eq(word_right_left(b"  one", 0), 2)
  assert_eq(word_size_left(b"\xe4\xb8\xad\xe6\x96\x87", 6), 6)
  assert_eq(word_right_left(b"\xe4\xb8\xad\xe6\x96\x87 x", 0), 7)
}
