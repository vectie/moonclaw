///|
/// System skills installer.
///
/// System skills are embedded at build time and installed into the
/// MoonLib-derived MoonClaw skills system directory. They are loaded with lower
/// priority than user/repo skills, so local skills can override by name.
const SYSTEM_SKILLS_DIR_NAME = ".system"

///|
const SYSTEM_SKILLS_MARKER_FILENAME = "system-skills.marker"

///|
fn moonclaw_skills_root(root : String) -> String {
  @moonsuite.product_artifact_for_workspace_root(root, "moonclaw", "skills")
}

///|
fn system_skills_root(home : String) -> String {
  moonclaw_skills_root(home) |> @pathx.join(SYSTEM_SKILLS_DIR_NAME)
}

///|
async fn install_system_skills(home : String, logger : @pino.Logger) -> Unit {
  let root = system_skills_root(home)
  @assets.install_assets(
    root,
    system_assets,
    system_assets_fingerprint,
    SYSTEM_SKILLS_MARKER_FILENAME,
    logger,
  )
}
