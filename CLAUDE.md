# CLAUDE.md

Personal Claude/claw skills. Each lives in `skills/<name>/` as a `SKILL.md` plus,
usually, a single shell script in `scripts/`.

## Writing a new skill

Start from `templates/SKILL.template.md`. It carries the section skeleton, and in
HTML comments the reasoning behind each section — read those, then strip them.

The one rule that isn't a section rule: **scripts do the work, the model routes.**
A SKILL.md documents a surface to invoke; it doesn't narrate a procedure for the
model to improvise against.

## Triggering and testing

The `description` field is the only thing that decides whether a skill fires, and
no template helps with it. Hand that to `skill-creator` — it has a description
optimizer and an eval loop. The template only covers the body.
