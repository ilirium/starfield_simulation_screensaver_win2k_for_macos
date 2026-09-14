# Naming the working-documents folder

Temporary working document. The folder in question will hold plans,
implementation notes, a backlog, and lessons learned — working material, as
opposed to the finished write-ups at the repository root.

`plans/` was rejected as too narrow. Nothing is decided; this is the long list.

---

## Criteria worth applying

Five things separate a name that ages well from one that irritates later.

1. **Tense neutrality.** The contents pull both ways — a backlog and plans
   point forward, lessons and implementation notes point back. Log-shaped
   names (`devlog`, `journal`, `logbook`) quietly imply a record of the past,
   so forward-looking items sit awkwardly in them.
2. **No collision with existing names.** `notes/` clashes with the root
   `NOTES.md`, which is the disassembly reference and carries real weight.
   `teardown/` clashes with `TEARDOWN.md` the same way.
3. **Convention freight.** `adr/`, `rfc/`, `specs/` are established names with
   expected formats. Borrowing one invites the convention along with it, and
   all three are narrower than what you want.
4. **Reads well if the repo goes public.** It is private now, but
   `internal/` or `wip/` would look odd on a public page in a way that
   `workshop/` would not.
5. **Sorts sensibly.** A lowercase folder sorts below the uppercase `*.md`
   files at the root in most listings, which is desirable — working material
   should not sit above the README.

---

## The long list

### Workspace metaphors — tense-neutral, "where the work happens"

| Name | Notes |
|---|---|
| `workshop/` | Broad, tense-neutral, no competing convention. Fits a project that is literally a teardown and rebuild. |
| `workbench/` | Same idea, more specific — a bench is where one thing is worked on at a time. Slightly long. |
| `bench/` | Terse. Collides conceptually with benchmarking, which may matter later. |
| `studio/` | Creative rather than mechanical connotation. Fine, slightly arty for reverse engineering. |
| `shop/` | Short, but reads commercial in a software repo. |
| `lab/` | Suggests experiments and spikes more than plans and backlog. |
| `garage/` | Informal, warm, implies tinkering. Reads unserious to some. |
| `forge/` | Strong, but taken by several products (SourceForge, Forgejo) and may confuse. |
| `drydock/` | Where a ship is opened up and repaired. Apt, memorable, arguably too clever. |
| `toolroom/` | Accurate but obscure. |

### Functional names — neutral, unambiguous

| Name | Notes |
|---|---|
| `engineering/` | Scales to anything. Never wrong. Slightly formal for a solo screensaver. |
| `development/` | Clear but long, and nearly everything in a repo is development. |
| `dev/` | Short, conventional, tense-neutral. Vague about what distinguishes it from the code. |
| `working/` | Literally correct — work in progress. Bland. |
| `process/` | Covers plans and retrospectives; sounds corporate. |
| `project/` | Too vague; the whole repo is the project. |
| `meta/` | Precise in one sense — documents *about* the project rather than the product — but abstract. |
| `internal/` | Clear separation from reader-facing docs. Odd in a solo repo, worse if public. |

### Notebook-shaped

| Name | Notes |
|---|---|
| `notebook/` | Broad and humble, no clash with `NOTES.md`. Suggests a book you add pages to. |
| `notes/` | The obvious choice, ruled out by the `NOTES.md` collision. |
| `memos/` | Implies short standalone documents; a backlog fits poorly. |
| `writings/` | Too literary. |
| `scratchpad/` | Implies disposable, which these are not. |

### Log-shaped — accurate for lessons, awkward for a backlog

| Name | Notes |
|---|---|
| `devlog/` | Familiar and clear. Past-tense bias is the only objection. |
| `journal/` | Same, slightly more personal. Suits dated entries. |
| `logbook/` | Nautical or laboratory connotation; pleasing for reverse-engineering work. |
| `log/` | Collides with runtime log output in most people's expectations. |
| `chronicle/`, `diary/`, `history/` | Increasingly past-tense; all fight the backlog. |

### Convention-bearing — narrower than the requirement

| Name | Notes |
|---|---|
| `adr/` | Architecture Decision Records, a real format. Decisions only. |
| `rfc/` | Numbered proposals. Proposals only. |
| `designs/`, `specs/` | Design documents only; no room for lessons or backlog. |
| `planning/`, `roadmap/` | The same problem that rejected `plans/`. |

---

## An alternative: no folder at all

Worth considering before committing to a directory, given the volume involved
is currently one document.

- **Single `WORKLOG.md` at the root.** Append-only, newest first. Zero
  structure to maintain. Becomes unwieldy past a few thousand lines.
- **A few root files** — `BACKLOG.md`, `LESSONS.md` — and plans only in a
  folder. Keeps the most-read items visible, but the root is already carrying
  five documents.
- **GitHub Issues for the backlog**, folder for everything else. Splits the
  backlog out of the repo entirely, which is either a feature or a nuisance
  depending on whether you want it offline.

A folder is probably right, but only because more plans are clearly coming.

---

## Structure inside, once named

Independent of the name, three shapes are common:

**Flat, date-prefixed** — chronology visible in the listing, no nesting:
```
workshop/2026-09-14-ci-and-distribution.md
workshop/2026-09-20-engine-tests.md
workshop/backlog.md
workshop/lessons.md
```

**Flat, numbered** — stable identifiers you can reference in commits:
```
workshop/0001-ci-and-distribution.md
workshop/0002-engine-tests.md
```
This is the ADR convention without the ADR template.

**Subfoldered by kind** — tidy, but heavy for a handful of files:
```
workshop/plans/  workshop/notes/  workshop/backlog.md  workshop/lessons.md
```

Recommendation: start flat and date-prefixed, with `backlog.md` and
`lessons.md` as fixed files alongside. Add subfolders only if the flat list
becomes hard to scan.

---

## Shortlist

If a decision is wanted without reading the whole list:

| | |
|---|---|
| `workshop/` | Best balance — tense-neutral, thematically apt, no baggage, reads fine publicly. |
| `engineering/` | Safest and most self-explanatory; slightly formal. |
| `notebook/` | Humble and broad, dodges the `NOTES.md` collision. |
| `devlog/` | Most familiar; accept the backlog tension or keep the backlog at the root. |

---

## Pending

- Folder name: **undecided**.
- `ci-and-distribution.md` sits at the repository root meanwhile, and moves
  once the name is chosen.
- `docs/` currently holds only the two README SVGs. If working documents get a
  home, those may read better in `assets/`, leaving `docs/` free or retired.
