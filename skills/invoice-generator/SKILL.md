---
name: invoice-generator
description: "Use this skill to generate PDF invoices from TOML configuration files. Activate when the user wants to create an invoice, bill a client, generate a factura, or produce billing documents — even if they don't explicitly mention 'invoicy', 'PDF', or 'TOML'."
version: "0.2.0"
---

# Invoice Generator

Generate PDF invoices from base TOML configs, filling in dynamic values like invoice number and dates.

## Prerequisites

- **Dependencies:** `invoicy` CLI (check with `invoicy --version`)
- **Environment:** `SKILLS_STATE_DIR` (optional; defaults to `<skill>/state`)

## Data Storage

Configs and invoices persist at:
```
$SKILLS_STATE_DIR/invoice-generator/
├── configs/     # Base TOML config files (user-provided)
└── invoices/    # Generated PDF outputs
```
If `SKILLS_STATE_DIR` is not set, defaults to `<skill>/state/invoice-generator/`.

## Usage

None — this skill uses the `invoicy` CLI directly.

| Command | Description |
|---------|-------------|
| `invoicy generate -c <config> -o <output>` | Generate a PDF from a config |
| `invoicy generate ... --set key=value` | Override or fill config values |
| `invoicy schema list` | List available invoice formats |
| `invoicy schema <format>` | Show the key paths for one format |

Three formats exist: `generic` (simple international), `afip_c` (Argentina, Monotributo), and `afip_a` (Argentina, Responsable Inscripto).

## Usage Examples

### List available configs
```bash
ls $SKILLS_STATE_DIR/invoice-generator/configs/
```

### Generate an invoice
```bash
invoicy generate \
  -c $SKILLS_STATE_DIR/invoice-generator/configs/client-name.toml \
  -o $SKILLS_STATE_DIR/invoice-generator/invoices/client-name-2025.05.pdf \
  --set invoice.number=2025.05 \
  --set invoice.date=2025-05-07 \
  --set invoice.due_date=2025-05-22
```

Those key paths are the `generic` ones. For `afip_c` / `afip_a` use `comprobante.numero`, `comprobante.fecha_emision`, `comprobante.fecha_vencimiento` — see Dynamic Fields below.

## Dynamic Fields

These are typically missing from base configs and filled at generation time. Key paths differ by format:

| Field | Default | `generic` | `afip_c` / `afip_a` |
|-------|---------|-----------|---------------------|
| Invoice number | `YYYY.MM` (e.g. `2025.05`) | `invoice.number` | `comprobante.numero` |
| Date | Today (`YYYY-MM-DD`) | `invoice.date` | `comprobante.fecha_emision` |
| Due date | Today + 15 days | `invoice.due_date` | `comprobante.fecha_vencimiento` |

Run `invoicy schema <format>` for the full field list of a format.

## Workflow

1. User asks to generate an invoice → list available configs in `configs/`
2. User picks a config (or specifies client name) → determine dynamic values
3. Apply defaults for missing config values unless user specifies otherwise: invoice number `YYYY.MM`, date today, due date today+15
4. User can override any defaults → adjust `--set` values accordingly
5. Run `invoicy generate` **with an explicit `-o`** pointing into `invoices/`
6. Confirm output path to user

## Gotchas

- `invoicy` does **not** deduplicate invoice numbers — it deduplicates *filenames*. A second run writes `invoice-2025.05_2.pdf` carrying the same number `2025.05` inside. Check `invoices/` before generating, or you'll silently issue a duplicate.
- Nothing is ever overwritten, including an explicit `-o` path — a second `-o out.pdf` produces `out_2.pdf`. To regenerate, delete the old file first.
- Always pass `-o`. Without it the PDF lands in the *current directory* as `invoice-{number}.pdf`, not in `invoices/`.
- Every config needs a top-level `format` key. `invoicy schema <format>` does **not** list it, so a config built from that output alone dies with `missing field 'format'`.
- Date format must be `YYYY-MM-DD`
- The `--set` flag uses dot notation for nested keys (e.g., `section.field`)
- If generation fails with missing fields, the error message names what's needed — prompt the user
- Config files contain sensitive info (client details, rates) — don't log full contents
- Output PDF naming: use `clientname-YYYY.MM.pdf` pattern for consistency
