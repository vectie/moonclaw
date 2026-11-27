///|
#derive(Debug)
priv suberror CopilotOAuthError {
  CopilotOAuthError(String)
}

///|
priv suberror ParseError {
  ParseError(String)
}
