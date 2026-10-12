///|
/// Explicit captured workspace for opt-in one-off work. Provider/config home
/// remains a separate GatewayJobApp concern. Existing agents.defaults.workspace
/// must not redirect a Town-owned frozen participant workspace.
pub async fn WorkspaceRuntime::captured(root : String) -> WorkspaceRuntime {
  {
    home: root,
    cwd: root,
    snapshot: load_workspace_snapshot_from_root(
      root,
      configured_from="captured-oneoff",
    ),
  }
}
