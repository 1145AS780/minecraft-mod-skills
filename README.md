# Minecraft Mod Development Skills

**English** | [中文](README.zh-CN.md)

A collection of skill documents for AI coding assistants working on Minecraft mod development. This repository contains documentation and scripts only — no mod source code, no third-party jars, no runtime artifacts.

## Contents

| Skill | What it does | Files |
| --- | --- | --- |
| [`skills/minecraft-mod-autopilot`](skills/minecraft-mod-autopilot) | Closed-loop automation for Forge 1.20.1 mods: write code → build → launch client → collect `latest.log` and `crash-reports` → locate and fix → re-verify. Ships build, launch, and diagnostic scripts plus an acceptance-level table | 9 |
| [`skills/minecraft-libraries`](skills/minecraft-libraries) | Multi-loader code reference library: Forge 1.20.1, NeoForge 1.21.1, Fabric 1.21.1, Paper plugins, vanilla datapacks, OptiFine/Iris shaderpacks | 27 |

A related but independent skill lives in its own repository: [`background-task-scheduler`](https://github.com/1145AS780/background-task-scheduler) — a local, daemon-free task scheduler for AI agents. It is loader-agnostic and shares no code with the skills here.

## Directory Layout

```
skills/
├── minecraft-mod-autopilot/
│   ├── SKILL.md                  Entry point: triggers and work loop
│   ├── references/               Documents loaded on demand
│   │   ├── forge-1.20.1-api.md
│   │   ├── error-triage.md
│   │   ├── automation-loop.md
│   │   └── ws-bridge.md
│   └── scripts/                  Directly callable scripts
│       ├── build.ps1
│       ├── run-client.ps1
│       ├── launch-pcl2.ps1
│       └── collect-diagnostics.ps1
├── minecraft-libraries/
│   ├── SKILL.md
│   ├── mod-loader-api/           Standard API references per loader
│   │   ├── forge-1.20.1.md
│   │   ├── neoforge-1.21.1.md
│   │   ├── fabric.md
│   │   ├── paper-bukkit.md
│   │   ├── datapack-1.20.1.md
│   │   ├── vanilla-datapack-nbt.md
│   │   ├── shaderpack-1.20.1.md
│   │   ├── version-migration.md
│   │   └── local-decompile.md
│   └── code-reference/
│       └── forge-1.20.1/         Battle-tested code and gotchas
```

## Conventions

| Rule | Detail |
| --- | --- |
| One skill, one directory | The directory name is the skill name, matching the name used in the `description` field of `SKILL.md` |
| `SKILL.md` is the only entry point | Assistants load just this file; the YAML `description` header decides when the skill triggers, and the body routes to deeper documents |
| `references/` is plural and flat | Topic-split documents use the plural name and sit directly under the skill root, with no further nesting |
| `scripts/` holds executables only | `.ps1` / `.py` files that can be invoked directly, no prose; scripts resolve the repo root themselves and never hardcode absolute paths |
| `code-reference/` is layered by loader | The first level is the loader name (e.g. `forge-1.20.1/`) with topic files flat beneath it, so a loader can be swapped or added wholesale |
| `examples/` lives under `references/` | Samples are documentation, not tooling, so they sit next to the specs that explain them |
| No build artifacts | `__pycache__/`, `.bak-*`, logs, and caches never enter the repository |

## Usage

Drop the skill directory you need into the skills folder of your assistant. No extra dependencies required.

The two skills compose well together: `minecraft-mod-autopilot` handles building and runtime verification, while `minecraft-libraries` supplies loader-specific APIs and real-world code references.

## Other Files

- [`LICENSE`](LICENSE): MIT
- [`README.zh-CN.md`](README.zh-CN.md): Chinese version
- [`ai-behavior-spec.md`](ai-behavior-spec.md): general AI behavior guidelines
- `.gitignore`, `.gitattributes`, `.aiignore`: repository and editor conventions

## Notes

- Mod IDs, package roots, and artifact names in the documents are written as placeholders such as `<modid>`, `<group>.<modid>`, and `<archivesName>`. They do not correspond to any specific project.
- Released under the [MIT License](LICENSE). Free to use, modify, and redistribute, provided the copyright notice is retained.