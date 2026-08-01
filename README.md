# skills

Personal agent skills — small, self-contained instruction sets that teach an agent to do one specific thing well. Each skill is a `SKILL.md` describing when to trigger and what to invoke, usually alongside a shell script that does the actual work.

## The skills

| Skill | What it does |
|---|---|
| [`carrefour.ar`](skills/carrefour.ar) | Search groceries, build a shopping list, generate a shareable Carrefour Argentina cart URL |
| [`cueva`](skills/cueva) | Record and query fees paid to exchange crypto for cash |
| [`gastos`](skills/gastos) | Track recurring household expenses in ARS + USD |
| [`invoice-email`](skills/invoice-email) | Assemble the email that accompanies an invoice from pre-approved snippets |
| [`invoice-generator`](skills/invoice-generator) | Generate PDF invoices from TOML configs |

## Layout

```
skills/<name>/
├── SKILL.md          # when to trigger, what to invoke
└── scripts/          # the work itself
templates/
└── SKILL.template.md # skill template
CLAUDE.md             # house style for writing new ones
```

## Creating new skills

Start from [`templates/SKILL.template.md`](templates/SKILL.template.md). It's the section skeleton with the reasoning for each section in HTML comments — read them, then strip them. [`CLAUDE.md`](CLAUDE.md) has the conventions.
