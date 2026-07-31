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

- **Dependencies:** `yq`
- **Environment:** `SKILLS_STATE_DIR` (optional; defaults to `<skill>/state`)

## How it works

`scripts/gen-email.sh` reads a client's template and prints a ready-to-send email. Because everything is copied verbatim, the email comes out in whatever language
the template is written in.

## Available scripts

- **`scripts/gen-email.sh`** — List clients with templates, generate email for clients.

## Usage

```bash
# List the clients that have a template
scripts/gen-email.sh --list

# Generate the email for one client
scripts/gen-email.sh -c <client>
```

`-c` accepts:
- a client name (resolved to `$SKILLS_STATE_DIR/invoice-email/configs/<client>.yaml`)
- or a direct path to a YAML file.

## Workflow

1. Identify the client from the request. If it's ambiguous or you're unsure a
   template exists, run `--list` and ask / pick the match.
2. Run `scripts/gen-email.sh -c <client>`.
3. Return the script's stdout **verbatim** as the email body. Don't add a subject
   line, commentary, or edits unless the user asks.
4. If the user wants a different mix (a task that's missing, a different length),
   that's a template change, not a one-off edit — see below.
