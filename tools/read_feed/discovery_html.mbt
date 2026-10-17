///|
priv struct DiscoveryTag {
  name : String
  closing : Bool
  attrs : Map[String, String]
}

///|
priv struct DiscoveryHtml {
  body : String
  lower : String
  mut pos : Int32
}

///|
// Preserve UTF-16 offsets, unlike Unicode case conversion of the whole input.
fn discovery_lower(value : String) -> String {
  String::from_array(
    value
    .to_array()
    .map(c => {
      if c is ('A'..<='Z') {
        (c.to_int() + 32).unsafe_to_char()
      } else {
        c
      }
    }),
  )
}

///|
fn discovery_space(c : UInt16) -> Bool {
  c is (' ' | '\t' | '\r' | '\n' | '\u{000C}')
}

///|
fn DiscoveryHtml::space(self : DiscoveryHtml) -> Unit {
  while self.pos < self.body.length() && discovery_space(self.body[self.pos]) {
    self.pos += 1
  }
}

///|
fn DiscoveryHtml::skip_to(self : DiscoveryHtml, token : String) -> Unit raise {
  guard self.lower[self.pos:].find(token) is Some(length) else {
    fail("Unclosed HTML section in feed discovery input")
  }
  self.pos += length + token.length()
}

///|
fn DiscoveryHtml::skip_declaration(self : DiscoveryHtml) -> Unit raise {
  let mut quote : UInt16? = None
  let mut brackets = 0
  while self.pos < self.body.length() {
    let c = self.body[self.pos]
    self.pos += 1
    if quote is Some(q) {
      if c == q {
        quote = None
      }
    } else if c is ('\'' | '"') {
      quote = Some(c)
    } else if c == '[' {
      brackets += 1
    } else if c == ']' {
      brackets = Int32::max(0, brackets - 1)
    } else if c == '>' && brackets == 0 {
      return
    }
  }
  fail("Unclosed HTML declaration in feed discovery input")
}

///|
// HTML permits bare ampersands. Decode common/numeric semicolon-terminated
// references; preserve unknown named references instead of guessing a URL.
fn discovery_entities(value : String) -> String {
  let out = StringBuilder()
  let mut pos = 0
  while pos < value.length() {
    if value[pos] == '&' {
      let mut semicolon : Int32? = None
      for end = pos + 1
          end < Int32::min(value.length(), pos + 17)
          end = end + 1 {
        if value[end] == ';' {
          semicolon = Some(end - pos)
          break
        }
      }
      if semicolon is Some(length) {
        let reference = value[pos:pos + length + 1].to_owned()
        let decoded = if reference == "&nbsp;" {
          Some("\u{00A0}")
        } else {
          Some(xml_entities(reference)) catch {
            _ => None
          }
        }
        if decoded is Some(decoded) {
          out.write_string(decoded)
          pos += length + 1
          continue
        }
      }
    }
    let c = value.get_char(pos).unwrap()
    out.write_char(c)
    pos += if c.to_int() > 0xffff { 2 } else { 1 }
  }
  out.to_string()
}

///|
fn DiscoveryHtml::next(self : DiscoveryHtml) -> DiscoveryTag? raise {
  while self.pos < self.body.length() {
    guard self.body[self.pos:].find("<") is Some(distance) else {
      self.pos = self.body.length()
      return None
    }
    self.pos += distance + 1
    if self.lower[self.pos:].has_prefix("!--") {
      self.pos += 3
      self.skip_to("-->")
      continue
    }
    // Declarations are skipped as text, never loaded or expanded.
    if self.pos < self.body.length() && self.body[self.pos] is ('!' | '?') {
      self.skip_declaration()
      continue
    }
    let closing = self.pos < self.body.length() && self.body[self.pos] == '/'
    if closing {
      self.pos += 1
    }
    let start = self.pos
    while self.pos < self.body.length() &&
          self.body[self.pos]
          is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '-' | ':') {
      self.pos += 1
    }
    if self.pos == start {
      continue
    }
    let name = self.lower[start:self.pos].to_owned()
    let attrs : Map[String, String] = Map([])
    while true {
      self.space()
      guard self.pos < self.body.length() else {
        fail("Unclosed HTML tag in feed discovery input")
      }
      if self.body[self.pos] == '>' {
        self.pos += 1
        break
      }
      if self.body[self.pos] == '/' {
        self.pos += 1
        continue
      }
      let start = self.pos
      while self.pos < self.body.length() &&
            !discovery_space(self.body[self.pos]) &&
            !(self.body[self.pos] is ('=' | '>' | '/' | '<' | '\'' | '"')) {
        self.pos += 1
      }
      guard self.pos > start else {
        fail("Malformed HTML attribute in feed discovery input")
      }
      let key = self.lower[start:self.pos].to_owned()
      self.space()
      let mut value = ""
      if self.pos < self.body.length() && self.body[self.pos] == '=' {
        self.pos += 1
        self.space()
        guard self.pos < self.body.length() else {
          fail("Missing HTML attribute value in feed discovery input")
        }
        if self.body[self.pos] is ('\'' | '"') {
          let quote = self.body[self.pos]
          self.pos += 1
          let start = self.pos
          while self.pos < self.body.length() && self.body[self.pos] != quote {
            self.pos += 1
          }
          guard self.pos < self.body.length() else {
            fail("Unclosed HTML attribute in feed discovery input")
          }
          value = self.body[start:self.pos].to_owned()
          self.pos += 1
        } else {
          let start = self.pos
          while self.pos < self.body.length() &&
                !discovery_space(self.body[self.pos]) &&
                self.body[self.pos] != '>' {
            self.pos += 1
          }
          value = self.body[start:self.pos].to_owned()
        }
      }
      // HTML's first duplicate attribute wins.
      if !attrs.contains(key) {
        attrs[key] = discovery_entities(value)
      }
    }
    return Some({ name, closing, attrs, })
  }
  None
}

///|
fn DiscoveryHtml::skip_raw(self : DiscoveryHtml, name : String) -> Unit raise {
  let token = "</" + name
  while true {
    guard self.lower[self.pos:].find(token) is Some(distance) else {
      fail("Unclosed HTML raw-text element in feed discovery input")
    }
    self.pos += distance + token.length()
    if self.pos < self.body.length() &&
      (
        discovery_space(self.body[self.pos]) ||
        self.body[self.pos] is ('>' | '/')
      ) {
      self.skip_to(">")
      return
    }
  }
}
