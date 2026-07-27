///|
/// True only for the canonical nonnegative decimal cursor encoding shared by
/// journal, stream, session, and conversation contracts. Magnitude is never
/// converted through a machine integer.
pub fn exact_cursor_is_canonical_nonnegative_decimal(text : String) -> Bool {
  if text == "0" {
    return true
  }
  let digits = text.to_array()
  if digits.is_empty() || digits[0] < '1' || digits[0] > '9' {
    return false
  }
  for digit in digits {
    if digit < '0' || digit > '9' {
      return false
    }
  }
  true
}

///|
fn require_exact_cursor(name : String, text : String) -> Unit raise {
  if !exact_cursor_is_canonical_nonnegative_decimal(text) {
    raise Failure::Failure(
      "MoonCode \{name} must be a canonical nonnegative decimal cursor",
    )
  }
}
