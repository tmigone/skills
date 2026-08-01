---
name: invoice-email
description: "Generate a client's invoice email by recombining pre-approved text from that client's YAML template. Use whenever the user wants to write, draft, or send the email that accompanies an invoice/factura for a client — e.g. 'draft the invoice email for Acme', 'invoice email for this month', 'email to go with the factura'."
---

# Invoice Email Generator

Produce the short email a freelancer sends alongside an invoice. Each client has
a YAML template of pre-approved snippets (openings, a heading, a task catalog,
closings). The email is **assembled by a script, not written by you**, your job
is to pick the right client and run the tool; do not compose, translate, reword,
or "improve" the email yourself.

## Prerequisites

- **Dependencies:** `yq` — specifically [mikefarah/yq](https://github.com/mikefarah/yq) (Go), not the Python package of the same name
- **Environment:** `SKILLS_STATE_DIR` (optional; defaults to `<skill>/state`)

## Data Storage

Client templates persist at:
```
$SKILLS_STATE_DIR/invoice-email/configs/<client>.yaml
```
If `SKILLS_STATE_DIR` is not set, defaults to `<skill>/state/invoice-email/`.

Each template holds the pre-approved snippets the script draws from:

| Key | Required | Purpose |
|-----|----------|---------|
| `opening` | yes | List; one entry becomes the first line |
| `closing` | yes | List; one entry becomes the last line |
| `report_heading` | no | List; one entry heads the task bullets |
| `report_tasks` | no | List; a subset becomes the bullets |
| `min_tasks` | no | Fewest bullets to include (default `3`) |
| `max_tasks` | no | Most bullets to include (default `6`) |

A template with only `opening` and `closing` is valid — it produces a two-line
email with no task report.

## Usage

- **`scripts/gen-email.sh`** — List the clients that have a template, or assemble one client's email

```bash
scripts/gen-email.sh [options]
```

| Command | Description |
|---------|-------------|
| `-l`, `--list` | List client names that have a template |
| `-c <client>`, `--config <client>` | Assemble the email for one client |
| `-h`, `--help` | Show usage and the resolved configs directory |

`-c` accepts either a client name — resolved to `<configs>/<client>.yaml`, then
`.yml` — or a direct path to a YAML file.

## Usage Examples

### See who has a template
```bash
scripts/gen-email.sh --list                     # one client name per line
```

### Generate the email
```bash
scripts/gen-email.sh -c acme                    # by client name
scripts/gen-email.sh -c /path/to/acme.yaml      # or a direct path
```
Prints the finished email on stdout, ready to send.

## Workflow

1. Identify the client from the request. If it's ambiguous or you're unsure a
   template exists, run `--list` and ask / pick the match.
2. Run `scripts/gen-email.sh -c <client>`.
3. Return the script's stdout **verbatim** as the email body. Don't add a subject
   line, commentary, or edits unless the user asks.

## Gotchas

- `yq` means mikefarah's Go build. The Python `yq` uses different expression syntax and fails on every call — check `yq --version` if the script errors oddly.
- Bullet count is clamped to the catalog: `min_tasks: 3` against a two-entry `report_tasks` quietly yields two bullets, not an error.
- `report_heading` is only printed when there are tasks to head. A template with a heading but no `report_tasks` produces just the opening and closing.
