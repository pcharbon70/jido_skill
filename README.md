# Jido.Code.Skill

Skill-only runtime for Jido-based markdown skills with signal-first dispatch.

## Terminal Commands

Build the local `jido` escript:

```bash
mix escript.build
```

Invoke a skill from terminal:

```bash
./jido --skill pdf-processor --route pdf/extract/text --data '{"file":"report.pdf"}'
```

Equivalent explicit form:

```bash
./jido --skill run pdf-processor --route pdf/extract/text --data '{"file":"report.pdf"}'
```

Mix task equivalent:

```bash
mix skill.run pdf-processor --route pdf/extract/text --data '{"file":"report.pdf"}'
```

## Guides

- User guides: `docs/user/`
- Developer guides: `docs/developer/`
- Acceptance contracts by phase: `docs/contracts/`
