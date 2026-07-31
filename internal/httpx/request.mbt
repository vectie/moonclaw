///|
/// Lightweight wrapper around an incoming HTTP request.
///
/// `RequestReader` exposes the request body as an `@io.Reader`, the HTTP
/// method, normalized request headers, the request path and any path variables
/// captured by the router.
pub struct RequestReader {
  /// Reader for the request body stream.
  body : &@io.Reader
  /// HTTP method of the request.
  method_ : Method
  /// Lower-case request header names as parsed by `moonbitlang/async/http`.
  headers : Map[String, String]
  /// Full request path as received by the server.
  path : StringView
  /// Route parameters extracted from the matched path pattern.
  vars : Map[StringView, StringView]
}
