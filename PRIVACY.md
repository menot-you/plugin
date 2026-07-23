# Privacy

nSOUL has no telemetry and sends no hook state to a network service.

## Default behavior

The shipped hooks persist no prompt, response, transcript, or session
identifier by default. The public hook does not implement automatic handoff.
Optional MCP services have their own privacy boundaries and do not become part
of nSOUL merely because an adapter can start them.

## Optional voice-lint state

Voice lint runs only when `NOTT_VOICE_LINT=on`. It reads the last assistant text
from the transcript path supplied by the host, classifies the final close in
the local process, and discards the text. Persistent state contains only:

- `ts` — UTC timestamp;
- `mode` — `warn` or `block`;
- `findings` — local rule classes and counts.

Prompt text, assistant text, transcript paths, and session identifiers are not
stored. The log retains at most 200 records and is created with private process
permissions under:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/nott/voice-lint.jsonl
```

Delete it at any time:

```sh
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/nott/voice-lint.jsonl"
```

`tests/hooks-test.sh` binds the reviewed hook bytes and enforces the behavior and
retention limit. The negative gate first proves a write-capable mutation reaches
an isolated sink, then requires the reviewed-byte binding to reject it.
