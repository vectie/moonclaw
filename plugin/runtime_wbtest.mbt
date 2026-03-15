///|
async test "plugin runtime loads entries and install state from config" {
  let dir = "/tmp/moonclaw-plugin-runtime"
  let config_path = dir |> @pathx.join("moonclaw.json")
  let install_path = dir |> @pathx.join("plugins") |> @pathx.join("feishu")
  @fsx.make_directory(install_path, recursive=true)
  @fsx.write_to_file(
    config_path,
    (
      {
        "plugins": {
          "entries": {
            "feishu": { "enabled": true },
            "demo": { "enabled": false },
          },
          "installs": {
            "feishu": {
              "source": "npm",
              "spec": "@openclaw/feishu",
              "installPath": install_path,
              "resolvedVersion": "1.0.0",
            },
          },
        },
      } : Json).stringify(),
  )

  let runtime = PluginRuntime::new(home=dir, cwd=dir)
  let plugins = runtime.list()
  inspect(plugins.length(), content="2")
  inspect(
    runtime.get("feishu").map(fn(p) { p.status }).unwrap_or(""),
    content="enabled",
  )
  inspect(
    runtime.get("demo").map(fn(p) { p.status }).unwrap_or(""),
    content="disabled",
  )
}
