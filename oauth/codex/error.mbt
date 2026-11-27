///|
#derive(Debug)
priv suberror OAuthError {
  OAuthError(String)
}

///|
priv suberror ParseError {
  ParseError(String)
}
