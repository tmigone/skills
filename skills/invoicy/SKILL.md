---
name: invoicy
description: "Use this skill to generate PDF invoices from TOML configuration files. Activate when the user wants to create an invoice, bill a client, generate a factura, or produce billing documents — even if they don't explicitly mention 'invoicy', 'PDF', or 'TOML'."
---

# Invoice Generator

Generate PDF invoices from base TOML configs, filling in dynamic values like invoice number and dates.

## Prerequisites

- **Dependencies:** `invoicy` CLI (check with `invoicy --version`)
- **Environment:** `SKILLS_STATE_DIR` (optional; defaults to `<skill>/state`)

## Available scripts

None — this skill uses the `invoicy` CLI directly.

## Commands

| Command | Description |
|---------|-------------|
| `invoicy generate -c <config> -o <output>` | Generate PDF from config |
| `invoicy generate ... --set key=value` | Override/set config values |
| `invoicy schema list` | List available invoice formats |
| `invoicy schema <format>` | Show schema for a format |

## Usage Examples

### List available configs
```bash
ls $SKILLS_STATE_DIR/invoicy/configs/
```

### Generate an invoice
```bash
invoicy generate \
  -c $SKILLS_STATE_DIR/invoicy/configs/client-name.toml \
  -o $SKILLS_STATE_DIR/invoicy/invoices/client-name-2025.05.pdf \
  --set <invoice_number_key>=2025.05 \
  --set <date_key>=2025-05-07 \
  --set <due_date_key>=2025-05-22
```

Use `invoicy schema <format>` to discover the correct key paths for each field.

## Data Storage

Configs and invoices persist at:
```
$SKILLS_STATE_DIR/invoicy/
├── configs/     # Base TOML config files (user-provided)
└── invoices/    # Generated PDF outputs
```
If `SKILLS_STATE_DIR` is not set, defaults to `<skill>/state/invoicy/`.

## Workflow

1. User asks to generate an invoice → list available configs in `configs/`
2. User picks a config (or specifies client name) → determine dynamic values
3. Apply defaults for missing config values unless user specifies otherwise: invoice number `YYYY-MM`, date today, due date today+15
4. User can override any defaults → adjust `--set` values accordingly
5. Run `invoicy generate` → PDF saved to `invoices/`
6. Confirm output path to user

## Dynamic Fields

These fields are typically missing from base configs and filled at generation time:

| Field | Default |
|-------|---------|
| Invoice number | `YYYY.MM` format (e.g., `2025.05`) |
| Date | Today (`YYYY-MM-DD`) |
| Due date | Today + 15 days (`YYYY-MM-DD`) |

Use `invoicy schema <format>` to find the correct key paths for each format.

## Gotchas

- Invoice numbers use `YYYY.MM` format; invoicy deduplicates automatically if collision
- Date format must be `YYYY-MM-DD`
- The `--set` flag uses dot notation for nested keys (e.g., `section.field`)
- Key paths vary by invoice format — check with `invoicy schema <format>`
- If generation fails with missing fields, error message indicates what's needed — prompt user
- Config files contain sensitive info (client details, rates) — don't log full contents
- Output PDF naming: use `clientname-YYYY.MM.pdf` pattern for consistency

## Technical Notes

- Uses Typst templates under the hood for PDF generation
- Supports multiple formats: `generic`, `afip_c` (Monotributo), `afip_a` (Responsable Inscripto)
- Run `invoicy schema <format>` to see all available fields for a format
- Single self-contained binary, no runtime dependencies
