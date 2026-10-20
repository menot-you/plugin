---
name: feedback
description: >-
  Report evidenced friction from this session's use of one module and provide
  a bounded diagnostic handoff for observed failures.
---

# Feedback

Turn this session's experience into evidence another engineer can investigate.

<!-- nott:feedback:read-only -->
Read available session evidence. Do not edit the product, dispatch repairs or
send an external message. Required session capture preserves the outcome; it
does not prove the report correct.

<!-- nott:feedback:window -->
The window is this session. Use actual calls and, where needed, native transcripts
resolved from session metadata. Do not invent a call, assume a complete trace or
sweep older sessions to manufacture friction.

<!-- nott:feedback:measure -->
Match observed tools to their registered module identity, never to a guessed
prefix. Useful signals include calls per tool, rejected arguments, typed refusals
and repeated attempts. Unused tools alone do not prove poor routing: the task may
not have needed them. Name missing telemetry.

<!-- nott:feedback:friction -->
Each reported friction names the relevant call, safe argument details, observed
reply and practical consequence. Rank by evidence. Separate observed failures
from usability observations and hypotheses; neither counts as the other.
Never include credentials or sensitive payloads.

<!-- nott:feedback:prompt -->
For an observed failure, end with one copyable prompt for /nott:debug containing
the required behavior, reproducer, candidate causes with rejecting observations,
and safe experiment boundaries. Do not invent a reproducer or send a papercut
into a diagnosis loop. When no observed failure supports such a prompt, report
that fact and omit the prompt.
