# Privacy

nSOUL has no telemetry and sends no hook state to a network service. Everything
described below is written to your own disk and read by nothing else.

## What the shipped hooks persist

Two hooks write local state. Neither is optional, and both are silent — nothing
they record is shown to you unless you open the file yourself.

## Voice-lint state

Voice lint runs on every `Stop`. There is no opt-in variable and no way to turn
it off; `NOTT_VOICE_LINT_MODE` selects `warn` (the default) or `block`, and
neither value disables the recording. It reads the last assistant text from the
transcript path the host supplies, classifies the closing paragraph in the local
process, and appends one JSON line **only when that classification finds
something**. A clean close writes nothing.

Each recorded line contains:

- `ts` — UTC timestamp;
- `session_id` — the session identifier the host supplied;
- `mode` — `warn` or `block`;
- `findings` — local rule classes and counts;
- `evidence` — at most the last 240 bytes of the closing paragraph of the
  assistant's own text.

So a recorded line DOES contain a short excerpt of assistant output and DOES
contain the session identifier. Your prompt text is never recorded, the
transcript path is never recorded, and no part of the transcript other than that
closing excerpt is ever recorded.

The file lives at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/nott/voice-lint.jsonl
```

**It is not private, and it is not bounded.** The hook creates the directory and
the file with your default permissions — observed `755` and `644`, so any local
account can read them — and nothing trims the file, which grows for as long as
findings keep occurring. Both are stated because they are what the code does; if
either matters to you, tighten the directory yourself or delete the file. Nothing
depends on its contents:

```sh
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/nott/voice-lint.jsonl"
```

## Auto-handoff state

`UserPromptSubmit` appends a reminder to the prompt context once a session has
run past a turn threshold, and it rate-limits itself with one small stamp file
per session:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/nott/autohandoff/<session-id>
```

The **file name is the session identifier** and the contents are a single unix
timestamp. No prompt text, assistant text, or transcript content is written.
Stamps older than seven days are deleted automatically on the next run. Delete
the directory at any time:

```sh
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/nott/autohandoff"
```

## Optional MCP services

Optional MCP services have their own privacy boundaries and do not become part
of nSOUL merely because an adapter can start them.
