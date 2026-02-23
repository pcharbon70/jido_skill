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

List discovered skills:

```bash
./jido --skill list
mix skill.list --scope local
```

Reload skills and settings from disk:

```bash
./jido --skill reload
mix skill.reload
```

Inspect active dispatcher routes:

```bash
./jido --skill routes
mix skill.routes --reload
```

Watch skill lifecycle and registry signals:

```bash
./jido --skill watch --limit 20
mix skill.watch --pattern skill.pre --pattern skill.post
```

Publish a skill signal manually:

```bash
./jido --skill signal skill.pre --data '{"skill_name":"pdf-processor","route":"pdf/extract/text"}'
mix skill.signal custom.health.check --data '{"status":"ok"}'
```

## Guides

- User guides: `docs/user/`
- Developer guides: `docs/developer/`
- Acceptance contracts by phase: `docs/contracts/`
