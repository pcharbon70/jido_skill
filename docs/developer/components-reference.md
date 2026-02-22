# Components Reference

This guide maps each runtime component to its responsibilities and API surface.

## `Jido.Code.Skill.Config`

Responsibilities:

- Read static app env defaults (`signal_bus_name`, middleware, paths).
- Expose canonical runtime paths (`global_path`, `local_path`, `settings_path`, `skill_paths`).
- Delegate structured settings loading to `Jido.Code.Skill.Config.Settings`.

Key functions:

- `signal_bus_name/0`
- `signal_bus_middleware/0`
- `global_path/0`, `local_path/0`, `settings_path/0`, `skill_paths/0`
- `load_settings/1`

## `Jido.Code.Skill.Config.Settings`

Responsibilities:

- Load optional global/local JSON settings files.
- Apply deep merge precedence (defaults <- global <- local).
- Validate strict allowed keys and field formats.
- Normalize bus names and middleware descriptors into runtime values.

Important behavior:

- Unknown keys are rejected at root, nested `signal_bus`, `permissions`, and `hooks` scopes.
- Hook config supports only `pre` and `post`.
- Hook `data_template` accepts only scalar JSON values.

## `Jido.Code.Skill.SkillRuntime.Skill`

Responsibilities:

- Define the skill behavior contract (`mount`, `router`, `handle_signal`, `transform_result`).
- Provide `__using__/1` defaults used by compiled skill modules.
- Compile `SKILL.md` frontmatter into runtime modules.

Important behavior:

- `handle_signal/2` matches normalized route path, emits `pre`, and returns `Jido.Instruction`.
- `transform_result/3` emits `post` and returns `{:ok, transformed_result, emitted_signals}`.
- Compiler validates frontmatter shape, resolves action modules, checks router references, and purges/rebuilds generated modules safely.

## `Jido.Code.Skill.SkillRuntime.SkillRegistry`

Responsibilities:

- Discover skills from global/local roots.
- Build cached `skill_entry` metadata used for dispatch.
- Evaluate permission status from `allowed-tools` plus `allow`/`deny`/`ask` patterns.
- Refresh skills/settings and publish registry update signals.

Public API:

- `get_skill/1`
- `list_skills/0`
- `hook_defaults/0`
- `bus_name/0`
- `reload/0`

Important behavior:

- Local skill entries override global entries when names collide.
- Same-scope duplicate names are deterministic (`Path.wildcard` sorted; first wins, rest logged).
- Reload publishes `skill.registry.updated` on both previous and refreshed bus names (when different) to support migration.

## `Jido.Code.Skill.SkillRuntime.SignalDispatcher`

Responsibilities:

- Subscribe to all discovered route signals.
- Dispatch incoming signals to the highest-priority matching skill.
- Execute instructions via `Jido.Exec.run/1`.
- Emit permission-blocked signals when permissions are `ask` or `denied`.
- Refresh subscriptions after registry updates.

Public API:

- `routes/0`
- `refresh/0`

Important behavior:

- Route normalization converts `a/b/c` to `a.b.c` for subscription/dispatch.
- Route conflict priority is local scope first, then lexical skill name.
- Refresh logic preserves cached subscriptions when registry reads, bus migration, or route subscribe steps fail.

## `Jido.Code.Skill.SkillRuntime.HookEmitter`

Responsibilities:

- Resolve effective `pre`/`post` hook config from frontmatter and global defaults.
- Interpolate template variables into payload data.
- Publish lifecycle signals safely without crashing caller modules.

Important behavior:

- `enabled: false` in frontmatter short-circuits emission.
- Runtime data fields override template collisions (`phase`, `skill_name`, `route`, `status`, `timestamp`).
- Signal type is published in dot form, source path remains slash form.

## `Jido.Code.Skill.Observability.SkillLifecycleSubscriber`

Responsibilities:

- Subscribe to lifecycle and permission-blocked signals.
- Dynamically refresh subscriptions when registry updates change hook signal types.
- Emit `:telemetry` event `[:jido_skill, :skill, :lifecycle]`.

Important behavior:

- Can refresh bus target from registry (`refresh_bus_name: true`) with fallback to cached/configured bus.
- Uses cached hook defaults/subscriptions when registry reads fail during refresh.
- Always includes permission-blocked signal subscriptions in target set.
