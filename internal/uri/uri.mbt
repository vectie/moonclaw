// URI parser implementation following RFC 3986

///|
pub struct Authority {
  mut userinfo : StringView?
  mut host : StringView
  mut port : Int?
} derive(Eq, Debug)

///|
pub struct Uri {
  mut scheme : StringView
  mut authority : Authority?
  path : Array[StringView]
  mut query : StringView?
  mut fragment : StringView?
} derive(Eq, Debug)

///|
suberror ParseError {
  InvalidScheme(StringView)
  InvalidPort(StringView)
  InvalidPercentEncoding(StringView)
  MissingColon
  MissingScheme
  ExtraContent(StringView)
  Eof
}

///|
fn Uri::parse_scheme(
  uri : Uri,
  source : StringView,
) -> StringView raise ParseError {
  match source {
    ['a'..='z' | 'A'..='Z', .. s] =>
      for rest = s {
        match rest {
          ['a'..='z' | 'A'..='Z' | '0'..='9' | '+' | '-' | '.', .. rest] =>
            continue rest
          [':', .. rest] as view => {
            uri.scheme = source
              .data()
              .view(
                start_offset=source.start_offset(),
                end_offset=view.start_offset(),
              )
            return rest
          }
          [_, ..] as rest => raise InvalidScheme(rest)
          [] => raise MissingColon
        }
      }
    [_, ..] as s => raise InvalidScheme(s)
    [] => raise Eof
  }
}

///|
test {
  let uri = Uri::{
    scheme: "",
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  let source = "http://example.com/path?query#fragment"
  json_inspect(
    uri.parse_scheme(source),
    content="//example.com/path?query#fragment",
  )
  json_inspect(uri.scheme, content="http")
}

///|
fn StringView::slice_until(self : StringView, other : StringView) -> StringView {
  self.view(end_offset=other.start_offset() - self.start_offset())
}

///|
fn parse_authority(
  source : StringView,
  uri : Uri,
) -> StringView raise ParseError {
  let authority = Authority::{ userinfo: None, host: "", port: None }
  uri.authority = Some(authority)
  fn parse_port(source : StringView) -> StringView raise ParseError {
    if source is [] {
      return source
    }
    let s = source
    for port = 0, rest = s {
      match (port, rest) {
        (port, ['/', .. k]) => {
          authority.port = Some(port)
          return parse_path_abempty(k, uri)
        }
        (port, ['0'..='9' as c, .. k]) =>
          continue port * 10 + c.to_int() - '0', k
        (port, [] as rest) => {
          authority.port = Some(port)
          return rest
        }
        (_, [_, ..] as rest) => raise InvalidPort(rest)
      }
    }
  }

  fn parse_host(source : StringView) -> StringView raise ParseError {
    let s = source
    for rest = s {
      match rest {
        [':', .. k] as rest => {
          authority.host = source.slice_until(rest)
          return parse_port(k)
        }
        ['/', .. k] as rest => {
          authority.host = source.slice_until(rest)
          return parse_path_abempty(k, uri)
        }
        [] as rest => {
          authority.host = source.slice_until(rest)
          return rest
        }
        [_, .. rest] => continue rest
      }
    }
  }

  let s = source
  let mut port_k = None
  for rest = s {
    match rest {
      ['@', .. k] as rest => {
        authority.userinfo = Some(source.slice_until(rest))
        return parse_host(k)
      }
      ['/', .. k] as rest =>
        if port_k is Some(port_k) {
          return parse_port(port_k)
        } else {
          authority.host = source.slice_until(rest)
          return parse_path_abempty(k, uri)
        }
      [':', .. k] as rest => {
        authority.host = source.slice_until(rest)
        port_k = Some(k)
        continue k
      }
      [] as rest => {
        authority.host = source.slice_until(rest)
        return rest
      }
      ['%', .. k] => {
        let mut b = 0
        let k = match k {
          ['0'..='9' as c0, .. k] => {
            b = (c0.to_int() - '0') * 16
            k
          }
          ['A'..='F' as c0, .. k] => {
            b = (c0.to_int() - 'A' + 10) * 16
            k
          }
          _ => raise InvalidPercentEncoding(k)
        }
        let k = match k {
          ['0'..='9' as c1, .. k] => {
            b = b + (c1.to_int() - '0')
            k
          }
          ['A'..='F' as c1, .. k] => {
            b = b + (c1.to_int() - 'A' + 10)
            k
          }
          _ => raise InvalidPercentEncoding(k)
        }
        continue k
      }
      [_, .. rest] => continue rest
    }
  }
}

///|
fn parse_fragment(source : StringView, uri : Uri) -> StringView {
  let s = source
  for rest = s {
    match rest {
      [] as rest => {
        uri.fragment = Some(source)
        return rest
      }
      [_, .. rest] => continue rest
    }
  }
}

///|
fn parse_query(source : StringView, uri : Uri) -> StringView {
  let s = source
  for rest = s {
    match rest {
      ['#', .. k] as rest => {
        uri.query = Some(source.slice_until(rest))
        return parse_fragment(k, uri)
      }
      [] as rest => return rest
      [_, .. rest] => continue rest
    }
  }
}

///|
fn parse_path_abempty(source : StringView, uri : Uri) -> StringView {
  let mut path = source
  for rest = source {
    match rest {
      ['/', .. k] as rest => {
        uri.path.push(path.slice_until(rest))
        path = k
        continue k
      }
      ['?', .. k] as rest => {
        uri.path.push(path.slice_until(rest))
        return parse_query(k, uri)
      }
      ['#', .. k] as rest => {
        uri.path.push(path.slice_until(rest))
        uri.fragment = Some(k)
        return k
      }
      [] as rest => {
        let part = path.slice_until(rest)
        if !part.is_empty() {
          uri.path.push(part)
        }
        return rest
      }
      [_, .. rest] => continue rest
    }
  }
}

///|
pub fn Uri::parse(source : StringView) -> Uri raise ParseError {
  let uri = Uri::{
    scheme: "",
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  let rest = parse_uri(uri, source)
  guard rest is [] else { raise ExtraContent(rest) }
  uri
}

///|
fn parse_uri(uri : Uri, source : StringView) -> StringView raise ParseError {
  fn parse_hier_part(source : StringView) -> StringView raise ParseError {
    match source {
      [.. "//", .. s] => return parse_authority(s, uri)
      [..] as s => {
        uri.authority = None
        return parse_path_abempty(s, uri)
      }
    }
  }

  fn parse_scheme(
    source : StringView,
    k : StringView,
  ) -> StringView raise ParseError {
    match k {
      ['a'..='z' | 'A'..='Z', .. s] =>
        for rest = s {
          match rest {
            ['a'..='z' | 'A'..='Z' | '0'..='9' | '+' | '-' | '.', .. rest] =>
              continue rest
            [':', .. k] as rest => {
              uri.scheme = source.slice_until(rest)
              return parse_hier_part(k)
            }
            [_, ..] as rest => raise InvalidScheme(rest)
            [] => raise MissingColon
          }
        }
      [_, ..] as s => raise InvalidScheme(s)
      [] => raise Eof
    }
  }

  match source {
    ['a'..='z' | 'A'..='Z', .. s] => return parse_scheme(source, s)
    [_, ..] as s => raise InvalidScheme(s)
    [] => raise MissingScheme
  }
}

///|
test {
  let uri = Uri::{
    scheme: "",
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_true(
    parse_uri(
      uri, "http://username:password@example.com:8443/path/to/resource?query=parameter#fragment",
    ).is_empty(),
  )
  assert_true(uri.scheme == "http")
  let authority = uri.authority.unwrap_or_error(
    Failure::Failure("Missing authority"),
  )
  assert_true(authority.userinfo == Some("username:password"))
  assert_true(authority.host == "example.com")
  assert_true(authority.port == Some(8443))
  assert_true(uri.path == ["path", "to", "resource"])
  assert_true(uri.query == Some("query=parameter"))
  assert_true(uri.fragment == Some("fragment"))
}

///|
test {
  let uri = Uri::{
    scheme: "",
    authority: None,
    path: [],
    query: None,
    fragment: None,
  }
  assert_true(
    parse_uri(uri, "http://username:password@example.com:8443/path/to/resource").is_empty(),
  )
  assert_true(uri.scheme == "http")
  let authority = uri.authority.unwrap_or_error(
    Failure::Failure("Missing authority"),
  )
  assert_true(authority.userinfo == Some("username:password"))
  assert_true(authority.host == "example.com")
  assert_true(authority.port == Some(8443))
  assert_true(uri.path == ["path", "to", "resource"])
  assert_true(uri.query == None)
  assert_true(uri.fragment == None)
}
