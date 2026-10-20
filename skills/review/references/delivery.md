# Pull-request delivery

One ask to review an exact pull request buys exactly one outward effect on that
target: one `COMMENT` review bound to the reviewed head. Never `APPROVE`, never
`REQUEST_CHANGES`, never an edit to the candidate. Everything below is the
mechanism that makes that one write safe to attempt and honest to report.

## Lock before deriving evidence

Pin, and re-read immediately before delivery:

1. `REPOSITORY` — `OWNER/NAME`, no path components.
2. `PULL_NUMBER` — a canonical positive integer.
3. `BASE_REF` — a valid Git branch name.
4. `BASE_COMMIT` — 40 lowercase hexadecimal characters: the pull request's
   `baseRefOid` observed when the review began. Preserve that observation in the
   completed review; the forge may report a newer base before publication.
5. `HEAD_COMMIT` — 40 lowercase hexadecimal characters.
6. `EXPECTED_LOGIN` — the login the write must be attributed to.
7. `BODY_SHA256` — the completed body's digest, 64 lowercase hexadecimal
   characters.
8. `BODY_FILE` — the body on disk, owned by the caller, group and other access
   denied, 1 to 65536 bytes of UTF-8.

Changed review bytes, reviewed work, actor or destination prevent delivery. A
new observed base alone does not: it changes neither the historical review nor
the work receiving the comment. Before publication, the reviewer revalidates
material policy, configuration and dependency changes under `checks.md`; the
helper publishes that review, never certifies merge readiness. An unrelated
trunk change requires neither rewriting the review nor repeating its checks.

## Body shape

The review body ends, below a Markdown thematic break, with exactly:

```
Reviewed candidate: REPOSITORY#PULL_NUMBER; base BASE_REF@BASE_COMMIT; head HEAD_COMMIT; actor EXPECTED_LOGIN
```

The helper refuses a body that does not end with that footer, and refuses a body
whose bytes no longer hash to the pinned digest. The digest is pinned after the
body is complete, never before.

## The helper

```
scripts/deliver-github-review.sh REPOSITORY PULL_NUMBER BASE_REF BASE_COMMIT HEAD_COMMIT EXPECTED_LOGIN BODY_SHA256 BODY_FILE
```

Invoked once per delivery. It needs `find`, `gh`, `git`, `head`, `iconv`, `id`,
`jq`, `ls`, `mkdir`, `mkfifo`, `mktemp`, `shasum`, `sleep`, `stat`, and `wc`.

What it does, in order: validate every argument by shape; open the body under a
private umask and verify its identity, ownership, mode, size, and UTF-8
decoding; verify the digest, then the footer; select a credential and scope it to
each child process; verify the active GitHub actor equals `EXPECTED_LOGIN`;
verify the pull request is open and its number, base repository, base ref and
head commit all match the pinned values; POST one `COMMENT` review
carrying `commit_id = HEAD_COMMIT`; read the posted review back and compare its
identifier, URL, commit, pull-request URL, author login, `COMMENTED` state, and
body digest; re-read the candidate to confirm it did not move during delivery.
An observed base advance during either target read does not invalidate the
publication. A changed reviewed head or destination still refuses; after POST,
that refusal preserves the no-retry warning.

Success prints one line, and it is the only receipt worth reporting:

```
review-delivery: posted and read back https://github.com/OWNER/NAME/pull/N#pullrequestreview-ID
```

## Refusal vocabulary

Every refusal ends in one of two phrases, and the difference is the whole point:

- **`no write attempted`** — the target is untouched. The gap is local:
  bad argument, unreadable or unsafe body, wrong digest, missing footer, absent
  credential, actor mismatch, candidate drift. Fix the named input and invoke
  once more.
- **`do not retry`** — the write may already exist. The POST was interrupted,
  timed out, returned no identifier, or the readback differed. Report the exact
  message as the gap.

No refusal escapes without one. The helper appends the phrase its delivery phase
dictates, so a message is never silent about the target's state, and ambiguity
always resolves toward `do not retry`: a refusal raised while the POST is in
flight says so even when its cause was local.

A second invocation after `do not retry` can post a duplicate review. Determine
whether the write occurred — read the pull request's reviews — before any
further outward action. An interrupt is handled the same way: the helper names
the phase it died in and, past the POST, tells you not to retry.

## Proof without a live call

This skill's delivery path is proven offline, by fixture and by the helper's own
pre-POST refusals — every one of them fires before any network call. A real POST
is a live mutation of someone's repository and belongs to the session that holds
the grant, not to a test.

Those checks are executable, not advice. `plugin/tests/review-delivery-skill-contract.sh`
runs them under a `gh` stand-in that refuses to be called and leaves a marker,
so a fixture that ever reached the network would be caught rather than trusted:

- `bash -n scripts/deliver-github-review.sh` — it parses.
- A fixture body whose bytes do not match the pinned digest: expect `review body
  changed after its digest was pinned; no write attempted`.
- A fixture body missing the candidate footer: expect `review body must end with
  the exact candidate footer; no write attempted`.
- A malformed `REPOSITORY`, `PULL_NUMBER`, commit, login, or digest: expect the
  matching argument refusal, still with no write attempted.
- Successful publication followed by exact review and target readback, including
  when only the observed base changes before or after POST: exactly one write.
- Changed reviewed head, destination repository/branch/number, or closed target:
  refuse before POST, or preserve `do not retry` after the single POST.
