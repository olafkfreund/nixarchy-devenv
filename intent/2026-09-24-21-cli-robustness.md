---
status: approved
issue: 21
author: olafkfreund
---

# Intent: the CLI degrades honestly when devenv's output is not what we expect

Closes #21, #22.

## Problem

Two places where the CLI's handling of devenv's output is looser than its own
documentation claims. Neither is dangerous today; both are the kind of thing
that bites exactly when upstream changes.

**The preset splice breaks in the case its fallback exists for (#21).** The
splice finds the last closing brace at column zero and inserts the preset
before it. A comment promises the preset goes before that brace, "never
nowhere". If devenv's scaffold ever has no such brace, the search yields
nothing, the arithmetic underflows to minus one, and the resulting `sed`
invocation fails and aborts the command mid-`init`. So the one scenario the
fallback is written to survive — upstream changing its scaffold — is the
scenario that breaks it. `init` leaves an unspliced file behind; `new` cleans
up after itself.

**A malformed process row is read as a running process (#22).** AGENTS.md says
only a `name status restarts: N` row is a process, and anything else must be
`unknown`, never `running`. The pattern requires only the literal `restarts:`,
not a numeric count, so a garbage line containing that word is counted as a
process and the environment is reported as running.

This one fails safe: removal refuses on both `running` and `unknown`, so the
consequence is an over-refusal, never a wrong deletion. It is still the stated
rule not holding.

Underneath both sits an assumption worth naming: every test runs against the
stub. Whether real devenv can print a process row while no manager is running,
or omit one while processes are running, has not been checked against a real
devenv. The second direction is the unsafe one.

## Proposed outcome

- A scaffold without a column-zero closing brace produces either a correctly
  appended preset or a clear refusal naming the unexpected scaffold — never an
  arithmetic underflow and a `sed` error.
- A malformed process row yields `unknown`, matching the documented rule.
- The assumption about real devenv's output is either verified against a real
  devenv or written down explicitly as an assumption in AGENTS.md.

## Affected users and systems

Anyone creating a project, and anyone whose removal is gated on process state.
Touches `pkgs/cli.sh` and `tests/cli.sh`, plus `tests/stub/devenv` if a
malformed-row fixture is needed. No QML or packaging changes.

## Constraints

- The status classification must stay fail-safe: anything unrecognised is
  `unknown`, and `unknown` continues to refuse removal.
- Tightening the row pattern must not start rejecting rows that real devenv
  legitimately emits — this needs a real sample, not a guess.
- Argv arrays only; the splice stays a file operation, not a shell string.
- Every behaviour change needs a test, per the existing rules.

## Open questions

1. For a scaffold with no column-zero brace: append the preset at the end of the
   file, or refuse with a message naming the unexpected scaffold? Appending
   keeps `init` working; refusing is louder and avoids writing something that
   may not evaluate.
2. Is it acceptable to tighten the process-row pattern without a sample from a
   real devenv? If not, this half waits on a machine with devenv installed.
3. Should verifying the real-devenv output assumption be part of this task, or
   its own issue against `templates-check` or a new integration check?
