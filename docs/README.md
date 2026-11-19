# Arcane documentation

Each folder answers one question. Start from the [project README](../README.md) to use the app; come here to understand or change it.

| Folder | Question it answers | Read it when |
|---|---|---|
| [how-it-works/](how-it-works/) | How does the app work today? | You want to understand an area before touching it. |
| [working-on-it/](working-on-it/) | How do I build, change and check it? | You are about to write code, run checks or release. |
| [history/](history/) | Why is it like this, and what was measured? | You need the evidence behind a past decision. Never needed to understand the present. |
| [media/](media/) | Which images does the README show? | You update screenshots. |

The guides in `how-it-works/` and `working-on-it/` are in Italian, except `development.md`.

## how-it-works/

| File | Contents |
|---|---|
| [architecture.md](how-it-works/architecture.md) | Every area of the app, its parts, its rules and its data on disk. |
| [flows.md](how-it-works/flows.md) | The main paths end to end: launch, library, Play, Add Game, saves, mods, settings, updates. |
| [steam.md](how-it-works/steam.md) | The Steam integration in full. |

## working-on-it/

| File | Contents |
|---|---|
| [development.md](working-on-it/development.md) | Prerequisites, builds, tests, CI and releases. |
| [conventions.md](working-on-it/conventions.md) | Where new code goes and the recipe for each kind of change. |
| [file-map.md](working-on-it/file-map.md) | One line per file of the project. |
| [validation.md](working-on-it/validation.md) | What the maintainer has tried in the app, and what still waits. |

## history/

| Folder | Contents |
|---|---|
| [engine-upgrades/](history/engine-upgrades/README.md) | One dated note per nxnative re-pin, with the checklist every re-pin follows. |
| [reviews/](history/reviews/) | Dated measurements and probes that back a choice described in the guides. |

## Reading order for a change

1. [AGENTS.md](../AGENTS.md), the project's rules.
2. [architecture.md](how-it-works/architecture.md), then [conventions.md](working-on-it/conventions.md).
3. [flows.md](how-it-works/flows.md), and the area's own document if it has one (for example [steam.md](how-it-works/steam.md)).
4. The files, through [file-map.md](working-on-it/file-map.md).
