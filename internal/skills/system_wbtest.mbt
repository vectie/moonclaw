///|
async test "system/install-writes-assets" (t : @test.Test) {
  @mock.run(t, mock => {
    let home = mock.cwd.path()
    let logger = @pino.logger("skills-system", @pino.Transport::console())
    let assets = [
      @assets.Asset::{
        path: "demo/SKILL.md",
        content: (
          #|---
          #|name: demo
          #|description: Demo system skill.
          #|---
          #|
          #|Hello.
        ),
      },
      { path: "demo/scripts/helper.py", content: "print('ok')\n" },
    ]
    let fingerprint = "test-fingerprint"
    let root = system_skills_root(home)
    assert_eq(
      root,
      @moonsuite.product_artifact(home, "moonclaw", "skills/.system"),
    )
    @assets.install_assets(
      root,
      assets,
      fingerprint,
      SYSTEM_SKILLS_MARKER_FILENAME,
      logger,
    )
    let skill_path = @pathx.join(root, "demo/SKILL.md")
    let script_path = @pathx.join(root, "demo/scripts/helper.py")
    let marker_path = @pathx.join(root, SYSTEM_SKILLS_MARKER_FILENAME)
    assert_true(@fsx.exists(skill_path))
    assert_true(@fsx.exists(script_path))
    assert_false(
      @fsx.exists(@pathx.join(root, ".moonclaw-system-skills.marker")),
    )
    inspect(@fsx.read_file(marker_path).trim(), content=fingerprint)
  })
}

///|
async test "system/install-marker-skips" (t : @test.Test) {
  @mock.run(t, mock => {
    let home = mock.cwd.path()
    let logger = @pino.logger("skills-system", @pino.Transport::console())
    let assets = [
      @assets.Asset::{ path: "demo/SKILL.md", content: "original\n" },
    ]
    let fingerprint = "skip-fingerprint"
    let root = system_skills_root(home)
    @assets.install_assets(
      root,
      assets,
      fingerprint,
      SYSTEM_SKILLS_MARKER_FILENAME,
      logger,
    )
    let skill_path = @pathx.join(root, "demo/SKILL.md")
    let marker_path = @pathx.join(root, SYSTEM_SKILLS_MARKER_FILENAME)
    @fsx.write_to_file(skill_path, "custom\n")
    @fsx.write_to_file(marker_path, fingerprint + "\n")
    @assets.install_assets(
      root,
      assets,
      fingerprint,
      SYSTEM_SKILLS_MARKER_FILENAME,
      logger,
    )
    inspect(@fsx.read_file(skill_path), content="custom\n")
    assert_false(
      @fsx.exists(@pathx.join(root, ".moonclaw-system-skills.marker")),
    )
  })
}
