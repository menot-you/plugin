#!/usr/bin/env sh
# UserPromptSubmit -> when a worker's completion reaches the session, remind the
# agent to dispatch the whole ready set, not the next item in reading order.
#
# Owner problem (2026-09-23): after every worker finished, the next units went
# out one at a time until the owner asked again. Owner decision: a
# REMINDER at that moment, never a block and never a denied call. Owner decision
# (2026-10-10): only units of the accepted result count as ready.
#
# THE MOMENT, measured on claude 2.1.281 (interactive and `-p`): a background
# Agent's completion arrives as a UserPromptSubmit whose prompt opens with
# `<task-notification>` and carries `<status>`; a Workflow's completion uses the
# same notification (the Workflow tool's own description says so); an nSPAWN
# run's notice arrives as a UserPromptSubmit whose prompt opens with
# `<cross-session-message` from `nspawn-supervisor` (mcps/nspawn/nspawn/notify.py).
# A Monitor event is a `<task-notification>` WITHOUT `<status>`: not a finished
# worker, so it stays silent. An owner turn stays silent unless it holds a list
# (below), so it never repeats on idle turns.
#
# No jq: the payload is matched as text, so a missing jq cannot mute it.
set -eu
payload=""
__line=""
while IFS= read -r __line || [ -n "$__line" ]; do
    payload="${payload}${__line}"
    __line=""
done

case $payload in
    # A background Bash command also ends in a `<task-notification>` with `<status>`, and its
    # summary opens `Background command`: it is not a worker (hook review).
    *'"prompt":"<task-notification>'*'<summary>Background command '*) exit 0 ;;
    *'"prompt":"<task-notification>'*'<status>'*|*'"prompt":"<cross-session-message '*'from-name=\"nspawn-supervisor\"'*)
        printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"A worker finished. Re-read the frontier and dispatch every ready independent unit of the accepted result together in one message, never new work; hold one back only for a missing input or a shared write-set. Order in a document is not a dependency."}}'
        exit 0 ;;
esac

# THE OWNER'S LIST (2026-10-19): one owner prompt held 12 numbered
# independent items and all 12 went to ONE agent; the rule shown at session start did not
# reach that act. An owner prompt with three or more item markers (`&<n>`,
# `<n>.`, `<n>)` or `- ` at a line start) gets the reminder in that turn. The owner gate is
# system1-suggest.py's `owner_prompt`: no subagent, nSPAWN child or `-p` run (`sdk-cli`), and
# no message delivered for someone else (its `NOT_OWNER`, copied in the awk below).
[ -z "${NOTT_NSPAWN_RUN_ID:-}" ] || exit 0
[ "${CLAUDE_CODE_ENTRYPOINT:-}" != sdk-cli ] || exit 0
items=$(printf '%s' "$payload" | awk '
    { s = s $0 }
    END {
        # A truthy agent_id (non-empty string, true, non-zero number) is a subagent; the
        # quotes cannot occur unescaped in a value.
        if (s ~ /"agent_id"[ ]*:[ ]*("[^"]|true|[1-9])/) { print 0; exit }
        if (!match(s, /"prompt"[ ]*:[ ]*"/)) { print 0; exit }
        s = substr(s, RSTART + RLENGTH)
        match(s, /^([^"\\]|\\.)*/)
        p = substr(s, 1, RLENGTH)
        # NOT_OWNER of system1-suggest.py, whatever the JSON spacing: a notification, a peer,
        # teammate or agent message. The contract checks this copy against that tuple.
        if (p ~ /^<(task-notification>|cross-session-message |teammate-message |agent-message )/) { print 0; exit }
        gsub(/\\\\/, "\001", p)
        n = split(p, line, /\\n/)
        c = 0
        for (i = 1; i <= n; i++)
            # `&1:` is an item; `1.5 s` is not, so only `<n>.` and `<n>)` need a space after.
            if (line[i] ~ /^ *(&[0-9]+|[0-9]+[.)]( |$)|- )/) c++
        print c
    }') || { printf 'fanout-reminder: awk failed; no owner-list reminder\n' >&2; exit 0; }
[ "$items" -ge 3 ] || exit 0

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"The owner prompt has %s list items. If you send these items to agents, send all independent items in parallel, in one message, with one writer for each write-set. Do not give all items to one agent. Hold back an item only for a named dependency, a shared write-set or an observed resource limit. Order in the list is not a dependency."}}\n' "$items"
