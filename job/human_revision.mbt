///|
fn human_revision_digest(bytes : Bytes) -> String {
  @capability.sha256_digest_ref_v1(bytes).text()
}

///|
fn human_revision_id(
  run_id : String,
  parent_id : String,
  save_id : String,
) -> String {
  let identity : Json = [run_id, parent_id, save_id]
  "human-" +
  human_revision_digest(@encoding/utf8.encode(identity.stringify()))[7:].to_owned()
}

///|
async fn ArtifactStore::human_revision_parent_unlocked(
  self : ArtifactStore,
  run_id : String,
  parent_id : String,
) -> (ArtifactRecord, String, String) {
  guard self.store.get_run(run_id) is Some(run) &&
    self.get(parent_id) is Some(parent) &&
    parent.run_id == run_id &&
    parent.job_id == run.job_id &&
    !parent_id.has_prefix("synthetic:") else {
    fail("Human revision parent does not belong to this retained run and job")
  }
  guard parent.content_type.has_prefix("text/") ||
    parent.content_type == "application/json" else {
    fail("Human revisions require retained UTF-8 text or JSON")
  }
  guard self.read_bytes(run_id, parent_id) is Some(bytes) else {
    fail("Human revision source is missing; restore it without rerunning work")
  }
  guard bytes.length() <= 8388608 else {
    fail("Human revision text exceeds the 8 MiB limit")
  }
  let content = @encoding/utf8.decode(bytes) catch {
    _ => fail("Human revisions require retained UTF-8 text or JSON")
  }
  guard @encoding/utf8.encode(content) == bytes else {
    fail("Human revisions require retained UTF-8 text or JSON")
  }
  (parent, content, human_revision_digest(bytes))
}

///|
/// Return exact host-owned source bytes and digest, without granting execution
/// authority. This snapshot is rechecked under the store lock when saving.
pub async fn ArtifactStore::human_revision_source(
  self : ArtifactStore,
  run_id : String,
  parent_id : String,
) -> Json {
  self.store.with_store_lock(async fn() {
    self.store.reload_artifacts_unlocked()
    let (parent, content, digest) = self.human_revision_parent_unlocked(
      run_id, parent_id,
    )
    {
      "artifact": parent.to_json(),
      "content": content,
      "revision_source": {
        "run_id": parent.run_id,
        "parent_digest": digest,
        "parent_version": parent.version,
      },
    }
  })
}

///|
/// Retain a human-authored copy. Identity, lineage, attribution, paths and run/job
/// metadata are host-owned. A save never changes the source or execution state.
/// Repeating the same save ID and bytes recovers its original durable record.
pub async fn ArtifactStore::save_human_revision(
  self : ArtifactStore,
  run_id : String,
  parent_id : String,
  save_id : String,
  expected_parent_digest : String,
  content : String,
  now_ms : Int32,
) -> ArtifactRecord {
  guard save_id.length() >= 8 &&
    save_id.length() <= 128 &&
    save_id
    .iter()
    .all(c => {
      (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '_'
    }) &&
    supervisor_digest_valid(expected_parent_digest) else {
    fail("Invalid human revision save ID or parent digest")
  }
  let bytes = @encoding/utf8.encode(content)
  guard (@encoding/utf8.decode(bytes) catch { _ => "" }) == content else {
    fail("Human revisions require retained UTF-8 text or JSON")
  }
  guard bytes.length() <= 8388608 else {
    fail("Human revision text exceeds the 8 MiB limit")
  }
  let id = human_revision_id(run_id, parent_id, save_id)
  let digest = human_revision_digest(bytes)
  self.store.with_store_lock(async fn() {
    self.store.reload_artifacts_unlocked()
    // Check confirmed replay before the current parent: a response can be lost
    // and the parent later changed. The exact committed copy is still the truth.
    if self.get(id) is Some(saved) {
      guard saved.run_id == run_id &&
        saved.artifact_type == "human_revision" &&
        saved.metadata
        is {
          "parent_artifact_id": String(saved_parent),
          "parent_digest": String(saved_expected),
          "save_id": String(saved_id),
          "content_digest": String(saved_digest),
          ..
        } &&
        saved_parent == parent_id &&
        saved_expected == expected_parent_digest &&
        saved_id == save_id &&
        saved_digest == digest &&
        self.read_bytes(run_id, id) == Some(bytes) else {
        fail("Save ID already records different human revision content")
      }
      self.store.save_artifacts_index_unlocked()
      return saved
    }
    let (parent, _, parent_digest) = self.human_revision_parent_unlocked(
      run_id, parent_id,
    )
    guard parent_digest == expected_parent_digest else {
      fail(
        "Parent content changed; keep your draft and reopen the source before saving",
      )
    }
    let lineage = if parent.artifact_type == "human_revision" {
      match parent.metadata {
        { "lineage_root_id": String(root), .. } => root
        _ => parent.id
      }
    } else {
      parent.id
    }
    let metadata : Json = {
      "schema": "moonclaw.human-revision.v1",
      "actor_kind": "human",
      "parent_artifact_id": parent.id,
      "parent_version": parent.version,
      "parent_digest": parent_digest,
      "content_digest": digest,
      "lineage_root_id": lineage,
      "save_id": save_id,
      "execution_output": false,
      "accepted_output": false,
    }
    self.write_bytes_unlocked(
      ArtifactBytesWriteRequest::from_text(
        ArtifactWriteRequest::new(
          run_id=parent.run_id,
          job_id=parent.job_id,
          artifact_type="human_revision",
          logical_key=Some(
            "human-lineage:" + human_revision_id(run_id, lineage, "lineage-v1"),
          ),
          content_type=parent.content_type,
          content~,
          metadata~,
        ),
      ),
      id,
      now_ms,
    )
  })
}
