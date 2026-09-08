# AI guidance

This directory exists so that a change request can be one sentence.

Saying *"bump Trivy to 0.75"*, *"add a team called analytics on GitLab"* or *"stop
blocking on MEDIUM findings"* should be enough — the agent reads
[`context.md`](context.md) for the facts and the relevant playbook for the procedure,
and does not need the architecture explained again.

| File | |
| --- | --- |
| [`context.md`](context.md) | Pinned versions, exact Azure strings, the build contract, and the change matrix |
| [`prompts.md`](prompts.md) | One-line requests that are known to work, and what each one triggers |
| [`playbooks/`](playbooks) | Step-by-step procedures for recurring changes |

## Keeping it useful

`context.md` is the single source of truth for anything an agent would otherwise guess:
versions, checksums, role GUIDs, Azure action strings, OIDC subject formats. When one of
those changes, change it there first — the playbooks and the guidance site both defer to
it.

The change matrix in `context.md` is the highest-value section. Most defects in a
repository shaped like this one are a change landing in three of the four places it
belongs. If you add a new fan-out — something that has to be edited in several files at
once — add a row for it.
