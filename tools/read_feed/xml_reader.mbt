///|
/// Small feed-oriented XML reader. No DTDs, external entities or network access.
priv struct FeedXml {
  name : String
  ns : String
  attrs : Map[String, String]
  children : Array[FeedXml]
  text : String
}

///|
priv struct XmlCursor {
  body : String
  mut pos : Int32
}

///|
fn XmlCursor::starts(self : XmlCursor, token : String) -> Bool {
  self.body[self.pos:].has_prefix(token)
}

///|
fn XmlCursor::space(self : XmlCursor) -> Unit {
  while self.pos < self.body.length() &&
        self.body[self.pos] is (' ' | '\t' | '\r' | '\n') {
    self.pos += 1
  }
}

///|
fn XmlCursor::until(self : XmlCursor, end : String) -> String raise {
  guard self.body[self.pos:].find(end) is Some(length) else {
    fail("Unclosed XML section")
  }
  let value = self.body[self.pos:self.pos + length].to_owned()
  self.pos += length + end.length()
  value
}

///|
fn XmlCursor::misc(self : XmlCursor) -> Unit raise {
  while true {
    self.space()
    if self.starts("<?") {
      self.pos += 2
      ignore(self.until("?>"))
    } else if self.starts("<!--") {
      self.pos += 4
      ignore(self.until("-->"))
    } else {
      break
    }
  }
}

///|
fn XmlCursor::name(self : XmlCursor) -> String raise {
  let start = self.pos
  while self.pos < self.body.length() &&
        !(self.body[self.pos]
        is (' ' | '\t' | '\r' | '\n' | '/' | '>' | '=' | '<' | '\'' | '"')) {
    self.pos += 1
  }
  guard self.pos > start else { fail("Expected XML name") }
  self.body[start:self.pos].to_owned()
}

///|
fn xml_entities(text : String) -> String raise {
  let out = StringBuilder::new()
  let cursor = XmlCursor::{ body: text, pos: 0, }
  while cursor.pos < text.length() {
    if text[cursor.pos] == '&' {
      cursor.pos += 1
      let entity = cursor.until(";")
      match entity {
        "amp" => out.write_char('&')
        "lt" => out.write_char('<')
        "gt" => out.write_char('>')
        "quot" => out.write_char('"')
        "apos" => out.write_char('\'')
        _ => {
          guard entity.has_prefix("#") else {
            fail("Unsupported XML entity: &\{entity};")
          }
          let hexadecimal = entity.has_prefix("#x")
          let value = @string.parse_int(
            entity[if hexadecimal { 2 } else { 1 }:],
            base=if hexadecimal { 16 } else { 10 },
          )
          guard value == 9 ||
            value == 10 ||
            value == 13 ||
            (
              value >= 32 &&
              value <= 0x10ffff &&
              !(value >= 0xd800 && value <= 0xdfff) &&
              value != 0xfffe &&
              value != 0xffff
            ) else {
            fail("Invalid XML character reference")
          }
          out.write_char(Char::from_int(value))
        }
      }
    } else {
      let c = text.get_char(cursor.pos).unwrap()
      out.write_char(c)
      cursor.pos += if c.to_int() > 0xffff { 2 } else { 1 }
    }
  }
  out.to_string()
}

///|
fn XmlCursor::element(
  self : XmlCursor,
  inherited : Map[String, String],
  depth : Int32,
) -> FeedXml raise {
  guard depth < 64 else { fail("XML nesting exceeds feed limit") }
  guard self.starts("<") && !self.starts("<!") && !self.starts("</") else {
    fail("Expected XML element; DTDs are unsupported")
  }
  self.pos += 1
  let qualified = self.name()
  let attrs : Map[String, String] = {}
  while true {
    self.space()
    if self.starts(">") || self.starts("/>") {
      break
    }
    let key = self.name()
    self.space()
    guard self.starts("=") else { fail("Expected XML attribute value") }
    self.pos += 1
    self.space()
    guard self.pos < self.body.length() && self.body[self.pos] is ('\'' | '"') else {
      fail("Expected quoted XML attribute")
    }
    let quote = if self.body[self.pos] == '\'' { "'" } else { "\"" }
    self.pos += 1
    guard !attrs.contains(key) else { fail("Duplicate XML attribute") }
    attrs[key] = xml_entities(self.until(quote))
  }
  let namespaces = inherited.copy()
  for key, value in attrs {
    if key == "xmlns" {
      namespaces[""] = value
    }
    if key.has_prefix("xmlns:") {
      namespaces[key[6:].to_owned()] = value
    }
  }
  let colon = qualified.find(":")
  let prefix = match colon {
    Some(i) => qualified[:i].to_owned()
    None => ""
  }
  let name = match colon {
    Some(i) => qualified[i + 1:].to_owned()
    None => qualified
  }
  guard prefix.is_empty() || namespaces.contains(prefix) else {
    fail("Undeclared XML namespace prefix")
  }
  let ns = namespaces.get(prefix).unwrap_or("")
  let children : Array[FeedXml] = []
  let text = StringBuilder::new()
  if self.starts("/>") {
    self.pos += 2
  } else {
    self.pos += 1
    while true {
      guard self.pos < self.body.length() else { fail("Unclosed XML element") }
      if self.starts("</") {
        self.pos += 2
        guard self.name() == qualified else {
          fail("Mismatched XML closing tag")
        }
        self.space()
        guard self.starts(">") else { fail("Invalid XML closing tag") }
        self.pos += 1
        break
      } else if self.starts("<![CDATA[") {
        self.pos += 9
        text.write_string(self.until("]]>"))
      } else if self.starts("<!--") {
        self.pos += 4
        ignore(self.until("-->"))
      } else if self.starts("<?") {
        self.pos += 2
        ignore(self.until("?>"))
      } else if self.starts("<") {
        let child = self.element(namespaces, depth + 1)
        if child.name is ("p" | "div" | "br" | "li" | "h1" | "h2") {
          text.write_char('\n')
        }
        text.write_string(child.text)
        if child.name is ("p" | "div" | "li" | "h1" | "h2") {
          text.write_char('\n')
        }
        children.push(child)
      } else {
        let start = self.pos
        while self.pos < self.body.length() && self.body[self.pos] != '<' {
          self.pos += 1
        }
        text.write_string(xml_entities(self.body[start:self.pos].to_owned()))
      }
    }
  }
  { name, ns, attrs, children, text: text.to_string(), }
}

///|
fn read_feed_xml(body : String) -> FeedXml raise {
  let cursor = XmlCursor::{
    body,
    pos: if body.has_prefix("\u{FEFF}") {
      1
    } else {
      0
    },
  }
  cursor.misc()
  let root = cursor.element({}, 0)
  cursor.misc()
  guard cursor.pos == body.length() else {
    fail("Unexpected content after XML feed")
  }
  root
}

///|
fn FeedXml::child(
  self : FeedXml,
  name : String,
  ns~ : String = self.ns,
) -> FeedXml? {
  for child in self.children {
    if child.name == name && child.ns == ns {
      return Some(child)
    }
  }
  None
}

///|
fn FeedXml::value(
  self : FeedXml,
  name : String,
  ns~ : String = self.ns,
) -> String? {
  match self.child(name, ns~) {
    Some(child) if !child.text.trim().is_empty() =>
      Some(child.text.trim().to_owned())
    _ => None
  }
}
