# Security policy

## Report privately

Use GitHub's private vulnerability reporting for `menot-you/nsoul`. If the
“Report a vulnerability” control is unavailable, open a public issue containing
only a request for a private contact channel. Do not include vulnerability
details, credentials, tokens, private transcripts, local paths, or operational
identifiers in that issue. Wait for the maintainer to establish the private
channel before exchanging details.

Include the affected release, operating system, client, minimal reproducer,
impact, and whether an optional MCP executable was configured. Redact local
paths unless the path shape is itself the defect.

## Security boundary

Security-sensitive surfaces are:

- plugin and marketplace manifests;
- command hooks and their local state;
- MCP executable resolution and argument forwarding;
- authority and instruction documents;
- release gates and their negative controls.

nMEMORY and nBrowser server implementations are external dependencies. The
adapter boundary is owned by `PRD.md` §7, and `SPEC.md` §2 states the controlled
proof basis. Repository checks use controlled local fixtures and cover only
candidate-local launcher behavior; mutable digest literals are regression
guards, not independent provenance. nSOUL does not attest to an external server
or an arbitrary executable selected from the host `PATH`.

## Maintainer checks

Every candidate must pass `bash tools/public-release-check.sh full` on the exact
bytes proposed for release and receive an independent read-only review. A local
green result proves neither remote CI nor public reachability. Public release,
credential use, and repository mutation remain separately authorized actions.

No ignore file or inline suppression may waive a secret-detector finding. Fix
the material or document a detector correction in the gate itself with a
negative control. CI installs the release-contract-pinned Gitleaks binary by
verified archive digest; local and CI scans use that binary's pinned built-in
rules while rejecting repository, environment, inline, and ambient-ignore
suppression. The authoritative historical content scan runs Gitleaks over every
commit tree materialized from raw Git objects; the merge-parent diff scan is
defense in depth. A separate raw corpus covers reachable commit and tag
metadata, ref names, and current or historical path names. Planted raw-tree,
merge-only, and metadata-only credentials are the negative controls for those
traversals. Authoritative Git history walks disable commit-graph acceleration;
a checksum-valid forged graph must not hide its raw parent.

The public repository is text-only: a NUL-bearing file is rejected before
content scanners run. Current hygiene and secret scans are also applied to every
reachable commit tree, so deleting private context in a later commit does not
make the earlier bytes publishable. The history walk parses raw Git tree
bytes with replacement resolution disabled for every namespace, rejects the
default replacement-ref namespace, on-disk object alternates, and legacy grafts,
rejects Git info attributes, and requires every logical ref to peel to a commit,
so attributes, normalized modes, forged graph parents, and colliding
materialization paths cannot conceal a commit-tree blob. The release gate pins
HEAD, direct-versus-symbolic logical-ref topology, and the declared Git control
files, including commit-graph state, across all client probes and rejects any
post-scan reachable-history change. Candidate-relative reads stay anchored to a
pinned current-directory root; close verifies that the original path still names
that same filesystem object, so a transient path replacement cannot redirect a
probe to substitute bytes.
