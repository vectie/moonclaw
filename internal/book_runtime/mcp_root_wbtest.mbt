///|
async test "MCP owner canonicalizes only the selected Book root" {
  let parent = @fs.realpath(@fs.tmpdir(prefix="book-mcp-owner-"))
  let root = parent + "/book"
  @fs.mkdir(root)
  @fs.symlink(parent + "/selected", target=root)
  let result = call_mcp(parent + "/selected", "mcp_list_tools", {})
  assert_true(flag(result, "ok"))
  assert_eq(array(result, "servers"), [])
}

///|
async test "MCP owner canonicalization retains descendant symlink refusal" {
  let parent = @fs.realpath(@fs.tmpdir(prefix="book-mcp-confined-"))
  let root = parent + "/book"
  @fs.mkdir(root)
  @fs.mkdir(root + "/.moonsuite")
  @fs.mkdir(root + "/.moonsuite/products")
  @fs.mkdir(root + "/.moonsuite/products/moonclaw")
  @fs.write_file(
    parent + "/outside.json",
    "{\"servers\":[]}",
    create_mode=CreateNew,
  )
  @fs.symlink(
    root + "/.moonsuite/products/moonclaw/mcp-servers.json",
    target=parent + "/outside.json",
  )
  assert_true(
    (Ok(call_mcp(root, "mcp_list_tools", {})) catch { error => Err(error) })
    is Err(_),
  )
}
