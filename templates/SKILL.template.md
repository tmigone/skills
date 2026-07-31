---
name: {{skill-name}}
description: "<What it does, then when to trigger. Include literal phrases the user would actually say — including ones that never name the tool. Close with a nudge for the non-obvious cases: 'even if they don't explicitly mention X'.>"
version: "x.y.z"
---

<!--
  House-style skeleton for this repo. The conventions behind it are in CLAUDE.md.
  Strip every HTML comment before shipping — they are guidance, not content.
  Drop a section when it genuinely has nothing to say.
-->

# {{Skill Title}}

<!--
  One paragraph: what this does, and for whom. If the domain has a term the
  model won't already know, define it right here, specially if sections after 
  it leans on that.
-->

## Prerequisites

<!--
  The contract for running this at all. Dependencies are binaries that must be
  on PATH. Environment is variables that must be exported. The script should
  fail loudly on each, so list them honestly — an undocumented dependency
  surfaces as a confusing runtime error.

  Anything deployment-specific belongs here rather than in the script:
  hostnames, base URLs, tokens, absolute paths. Hardcoding them pins the skill
  to one machine — no staging deployment, no second user, and a move of hosts
  becomes a code change. It's also what decides whether the repo can ever be
  published.
-->

- **Dependencies:** `binary1`, `binary2` (optional)
- **Environment:** `EXAMPLE_ENV_VAR` (explanation)

## Data Storage

<!--
  Only for skills that persist something locally, could be configuration or
  output. Give the exact path and the fallback. Delete this section entirely 
  for stateless skills.
-->

State persists at:
```
$SKILLS_STATE_DIR/{{skill-name}}/
```
If `SKILLS_STATE_DIR` is not set, defaults to `<skill>/state/{{skill-name}}/`.

## Usage

<!--
  What the skill is driven by. The reader should leave this section knowing
  exactly what to invoke — or knowing there is nothing to invoke, which is
  just as useful.

  Skills come in three shapes. Pick one and delete the scaffolding for the
  other two:

  1. BUNDLED SCRIPT — list the script(s), then the canonical invocation and a
     command table.
  2. EXTERNAL CLI — say so outright ("None — this skill uses the `foo` CLI
     directly"), then table the subcommands actually used. Don't restage the 
     CLI's own `--help`; cover the handful this skill relies on.
  3. NO TOOLING — the skill is instructions. Drop the script list and the
     table entirely; instead say what inputs it works from, where they live,
     and what shape they're in. Something still has to be concrete here, or
     the section is just throat-clearing.

  The table is the reference surface: one row per command, defaults noted
  inline, no prose. Prose belongs in Usage Examples.
-->

- **`scripts/{{skill-name}}.sh`** — <one line: what it does, what it reads, what it writes>

```bash
scripts/{{skill-name}}.sh <command> [args]
```

| Command | Description |
|---------|-------------|
| `<command>` | <what it does; note defaults inline, e.g. "(default: current month)"> |

## Usage Examples

<!--
  Copy-pasteable lines with a trailing `#` comment on each. These get read far
  more often than the table above, so cover the common shapes: no-args, with a
  filter, with a range. Say what comes back and what to do with it..
-->

### <What the user is trying to do>
```bash
scripts/{{skill-name}}.sh <command>              # <what this returns>
scripts/{{skill-name}}.sh <command> --flag val   # <the filtered variant>
```

## Workflow

<!--
  Numbered, and each step maps a USER INTENT to a command — not a description
  of the script's internals. This is the section that decides whether the model
  picks the right command from a vague request, so lead each step with the
  thing the user actually said.

  Include the resolution steps that are easy to skip.
-->

1. User says "<something vague>" → `scripts/{{skill-name}}.sh <command>` → <how to read the result>.
2. <...>
3. Report back what was read or written so the user can confirm.

## Gotchas

<!--
  The failure modes you only learn by running this in anger. Real ones from
  this repo: `month` is 0-indexed in one command and `YYYY-MM` in another; a
  recorded `0` means handled, not missing; `location` matches case-sensitively;
  the API returns `price: 0` for unavailable items; cart URLs break past ~4000
  characters.

  This is also where backend behaviour goes, when it changes what the agent
  should do: a write that upserts rather than appends, a hard cap on how much
  you can send, a fixed sort order, a sentinel value that means "unavailable".
  Facts about how the backend is BUILT — the framework, the database, the
  binary — belong in a comment in the script, which is never loaded into
  context. This file is, every time the skill fires.

  The test: each bullet should describe something that would produce a wrong
  answer or a silent failure, not something already obvious from the table
  above. If you can't name two, you probably haven't used the thing yet — go
  use it, then come back.
-->

- <the surprising one>
- <the one that silently produces a wrong answer>
- <the argument that must be quoted / typed / resolved first>
- <the write that overwrites instead of appending, or the limit you'll hit>
