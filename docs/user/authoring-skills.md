# Authoring Skills

Skills are markdown files (`SKILL.md`) with YAML frontmatter. They compile into runtime modules and are discovered from global and local skill roots.

## Where to Put Skills

- Global: `~/.jido_code/skills/<skill-dir>/SKILL.md`
- Local: `.jido_code/skills/<skill-dir>/SKILL.md`

If a skill name exists in both scopes, local overrides global.

## Required Frontmatter

- `name`
- `description`
- `version`
- `jido.actions` (non-empty list)
- `jido.router` (non-empty list)

Optional:

- `allowed-tools`
- `jido.skill_module`
- `jido.hooks.pre`
- `jido.hooks.post`

## Minimal Valid Example

```yaml
---
name: pdf-processor
description: Extract text from PDFs
version: 1.0.0
allowed-tools: Read, Write, Bash(python:*)
jido:
  actions:
    - MyApp.Actions.ExtractPdfText
  router:
    - "pdf/extract/text": ExtractPdfText
  hooks:
    pre:
      enabled: true
      signal_type: "skill/pdf_processor/pre"
      bus: ":jido_code_bus"
      data:
        source: "frontmatter"
    post:
      enabled: true
      signal_type: "skill/pdf_processor/post"
      bus: ":jido_code_bus"
      data:
        source: "frontmatter"
---

# PDF Processor
```

## Router and Action Rules

- Route path format: slash-delimited lower-case segments (`a-z`, `0-9`, `_`, `-`).
- Router action references must resolve to declared action modules.
- Action modules must be loadable (`Code.ensure_loaded?`).

Signal routing normalization:

- Frontmatter route `pdf/extract/text` is subscribed as `pdf.extract.text`.

## Hook Rules

- Only `pre` and `post` are allowed.
- Hook keys allowed: `enabled`, `signal_type`, `bus`, `data`.
- `enabled: false` disables that hook.
- Missing hook fields are allowed and can fall back to global defaults.

## `allowed-tools` and Permissions

`allowed-tools` is a comma-separated string. The registry classifies each skill as:

- `:allowed`
- `{:ask, tools}`
- `{:denied, tools}`

based on runtime permissions from settings.

## Common Validation Errors

- Missing required fields (`name`, `description`, `version`, actions, router).
- Unknown `jido` keys (for example `command` is not supported).
- Invalid router path format (uppercase or unsupported characters).
- Invalid hook keys or hook `signal_type` format.
- Unresolved action modules.
