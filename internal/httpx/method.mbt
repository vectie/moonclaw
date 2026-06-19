///|
/// HTTP request methods supported by the `httpx` router.
pub(all) enum Method {
  Get
  Head
  Post
  Put
  Delete
  Connect
  Options
  Trace
  Patch
} derive(Eq, Compare, Hash, ToJson)

///|
pub impl Show for Method with fn to_string(self : Method) -> String {
  match self {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
}

///|
pub impl Show for Method with fn output(self : Method, out : &Logger) -> Unit {
  out.write_string(self.to_string())
}

///|
/// Array containing all supported HTTP methods.
pub let methods : Array[Method] = [
  Get,
  Head,
  Post,
  Put,
  Delete,
  Connect,
  Options,
  Trace,
  Patch,
]

///|
fn Method::from_async_http(method_ : @http.RequestMethod) -> Method {
  match method_ {
    Get => Get
    Head => Head
    Post => Post
    Put => Put
    Delete => Delete
    Connect => Connect
    Options => Options
    Trace => Trace
    Patch => Patch
  }
}

///|
/// Converts a `Method` into the corresponding `@http.RequestMethod` value.
pub fn Method::to_http(self : Method) -> @http.RequestMethod {
  match self {
    Get => Get
    Head => Head
    Post => Post
    Put => Put
    Delete => Delete
    Connect => Connect
    Options => Options
    Trace => Trace
    Patch => Patch
  }
}
