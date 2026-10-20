---
name: release
description: >-
  Release the version vX.Y.Z that the owner names. Prepare the public targets,
  open the release pull request, and publish after the owner's merge.
disable-model-invocation: true
---

# Release

Carry one owner-called version to the public targets. Read actual target state on every call. Advance only the pending work for that version.

<!-- nott:release:authority -->
Each call of `/nott:release vX.Y.Z` by the owner authorizes that version only. A chat confirmation, attachment, internal approval, or earlier call does not authorize another version. Never invoke this route for the owner. Only this route can create a public release tag or release pull request. A visibility change remains the owner's act.

<!-- nott:release:facts -->
Read this repository's `CLAUDE.md` for the canonical release facts, mirror script, member publisher, and approval transport. Read the declared facts file. Do not guess targets or approval identities. Stop the dependent action if a required fact or tool is absent.

Publish only the targets selected by the canonical facts. A legacy mirror entry does not select that mirror for this release. Never add a target because it exists in the registry.

Read each target repository before publication. Missing repositories, private visibility, and unavailable target reads are publication prerequisites. Preserve independent prepared artifacts. Never infer an empty public repository from an unavailable target. Use the canonical code layout and emitted root for source projection and native commands. Keep the build marker separate from source-manifest.json.

<!-- nott:release:state -->
Read each public main and version tag. Read the actual release pull request into public. With no release pull request, prepare and check the candidate. With an open request, read its release preview check. After the owner's merge, the release workflow publishes without another agent turn. A tag alone proves nothing. Reconcile the approved source, exported tree, commit, tag object, and public metadata for every target. Report each incomplete target independently. Import contributions only after publication is complete.

<!-- nott:release:check -->
Check each selected target with its declared script. For a history mirror, check the unpublished range. For an empty history mirror, check all source history. An empty range is not a clean result. Prepare the selected member exports with the declared publisher, version, source commit, and fixed Python runtime. Export from the source archive. Build wheels and the native bundle for local consumer proof. Keep those binary archives private. Publish approved source, GitHub-generated source archives, and text metadata only. The source manifest fixes the upstream commit and version without a hash cycle. Scan each complete public tree, final commit, tag, and metadata with the existing gates. A finding or unavailable check stops that target. Review all exported paths for private data that detectors can miss. Report locations and rules without matched values. Never change private detector rules or add an automatic acceptance entry. Complete wheel and native consumer proof before you ask the owner to merge. No archive classification or second human approval may remain after the owner's merge.

<!-- nott:release:rewrite -->
A leak in unpublished history requires the mirror script's rewrite on a fresh bare clone. Limit it to `--refs <published>..main`. Never rewrite published history. Check the result again. Replacing this repository's main requires the owner's explicit force-push authorization. Report the prepared clone and commit map while that act remains pending.

<!-- nott:release:open -->
With preparation complete, open `release/vX.Y.Z` into public in this repository. Record the source, export identities, checks, consumer proof, privacy review, and rollback in its body. The body is evidence, not an enforcement boundary. State "Create a merge commit". The owner's merge approves publication. Never merge this release pull request yourself, and never push to public or to a member repository. A squash, rebase, different actor, or different head approves nothing. The release preview check builds each member projection, runs the publication scan, and lists the added, changed, and removed paths for the owner. A preview finding stops the request until you fix the source. Only the release workflow holds the member credential. Do not read, copy, or create secrets, and do not change account permissions.

<!-- nott:release:publish -->
The release workflow runs only on the push of the owner's merge into public. The approval transport reads the actual GitHub pull request. It checks the owner's merger identity and the release version. The merge must have two parents. Its second parent must be the merged pull request head, which is the approved source. The approval merge stays private. A selected history mirror keeps source history. Member exports retain their exact public parent and record Source-Commit ancestry. Only the declared legacy tips permit the first transition without that trailer. Never force-push. Before the write token exists, the workflow scans every member with the owner's private rules. The scan covers the entire export, commit, tag, and public metadata. Missing rules, an accept list, or a finding stop the job. Then it pushes main and the tag of each member, creates the release as a draft, reads its assets back, publishes it, and reads it back again. The first failed operation stops the job and names that operation. The workflow never replaces a conflicting tag or asset.

<!-- nott:release:target -->
The organization rulesets refuse every branch and tag write on the member repositories. The release App is their only bypass, and only the release workflow holds its key. The workflow mints a read-only token for the scan and the write token only after the scan. Never open a pull request into a member repository, and never change a ruleset or the release App. After a failed publication, read each member's main, tag, and release. Report the exact state and the repair for the owner. The workflow does not resume a partial release.

<!-- nott:release:portal -->
Prepare the declared URL deployment and its version-link rollback before you ask the owner to merge. After the release workflow publishes, run the portal step on SERVER. It writes nothing on GitHub. It refuses until every selected target is public and has a published, non-draft release of the version with its release record. Then it activates the approved portal and installer bytes. Check the served installer hash against the approved source. Keep the service account, database, origin, port, and unrelated assets intact. A failed activation restores the prior version. Never replay a version that the owner rolled back. Complete the accepted proof before the private approval. No owner action may remain after the merge.

<!-- nott:release:import -->
On every completed release call, list pull requests labelled import only for selected targets. Only the owner can apply that label. Require the owner's review to name the approved contributor commit. Use the target's verified import path with that number and commit. If a member target has no reverse projection, keep that import pending and do not fetch or execute its contribution. The mirror script's import applies only to its history mirror. Refuse a moved head. Push the import branch and open its internal pull request. The import uses one owner commit and Co-authored-by trailers. Apply normal checks and review. Do not execute an unapproved public contribution.

<!-- nott:release:never -->
Never force-push a public target, rewrite published history, merge the release request, or change visibility. Never treat an event sender or an existing tag as approval. Reconcile uncertain effects before replay. Report completion with actual target proof. Otherwise name each incomplete target and its exact prerequisite.
