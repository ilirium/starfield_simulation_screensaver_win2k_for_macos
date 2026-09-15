# Handoff

Where the project stands, what is decided, what is not, and what to distrust.
Written 2026-09-14.

`CLAUDE.md` tells a new session how to work in the repo. This file is the
state of play.

---

## What exists and works

A macOS screen saver reproducing the Windows 2000 "Starfield Simulation"
(`ssstars.scr`, 5.00.2195.6601). **Installed and confirmed working** on macOS
26.6.2, Apple Silicon.

```sh
./build.sh                                   # builds, signs, self-verifies
cp -R build/Starfield.saver ~/Library/"Screen Savers"/
```

`build.sh` produces four things and runs `LoadTest` against the bundle, so a
broken build fails loudly rather than at screen-blank time:

| | |
|---|---|
| `build/Starfield.saver` | the plugin, ad-hoc signed |
| `build/StarfieldPreview` | the saver in a normal window; `[density] [warp]` |
| `build/Render` | offscreen PNG frames, and `--svg docs/assets` regenerates the README art |
| `build/LoadTest` | loads a `.saver` as macOS does; non-zero exit on failure |

Command Line Tools are sufficient. There is no Xcode project, no package
manifest, no dependencies.

---

## Repository map

```
Sources/          engine (pure Int math), view (AppKit), config sheet, preview main
Tools/Render/     offscreen renderer + SVG generator
Tools/LoadTest/   bundle verification
Tools/pe-imports.py   PE import-table dumper, how the teardown started
Resources/        Info.plist (NSPrincipalClass = StarfieldView)
docs/             the two README SVGs (generated, do not hand-edit)
```

Documentation, in reading order:

| | |
|---|---|
| `README.md` | front page: install, build, settings, pointers |
| `docs/WIN32-PRIMER.md` | how the original and Win32 work; assumes no Windows background |
| `docs/TEARDOWN.md` | how the binary was disassembled, including the wrong turns |
| `docs/HOW-IT-WORKS.md` | how the Swift port works; assumes no Swift/AppKit/ObjC |
| `docs/NOTES.md` | bare reference: every constant with its address |

Working documents, at the root **temporarily**:

| | |
|---|---|
| `ci-and-distribution.md` | researched plan for CI, universal builds, signing, packaging |
| `folder-naming-options.md` | ~35 candidates for the folder these two should live in |

---

## Git state

Work is on **`macos-port`**. `main` is still at the initial commit and nothing
has been merged. Five commits on the branch:

```
c99f4a0  CI and distribution research, folder naming options
6b52d2e  the third GDI import, and a real README
db771e9  Win32 primer
3042ba3  teardown and port documentation
b8720cb  the port itself
```

To land it: `git checkout main && git merge --ff-only macos-port && git push`.

The repository is **private**. `bin/ssstars.scr` is gitignored by your choice
and is Microsoft's; nothing in the build reads it.

---

## Decisions already made

- **Source only, no binaries committed.** Chosen deliberately; `build/` is
  gitignored. The README illustrations are SVG specifically so they stay text.
- **Fidelity over modernisation.** Truncating integer division, the speed ramp
  inside the per-star loop, the MSVC LCG — all reproduced on purpose.
  `docs/NOTES.md` lists the four deliberate deviations. Do not "fix" these.
- **20 fps**, matching the original's 50 ms timer. A smooth-motion mode was
  offered and not taken up; it remains available if wanted.
- **No `Claude-Session` trailer** in commits. Turned off in
  `~/.claude/settings.json` via `attribution.sessionUrl: false`;
  `Co-Authored-By` was kept.

---

## Open decisions

**The working-documents folder name.** Shortlist `workshop/`, `engineering/`,
`notebook/`, `devlog/`; full reasoning in `folder-naming-options.md`. Once
chosen, move both root working documents into it.

**The five CI questions** at the end of `ci-and-distribution.md`: deployment
target (13.0 recommended), universal vs arm64-only, whether to pay $99/year
for signing, whether the repo stays private, and whether tests come before CI.

**`docs/` holds only the two SVGs**, which may read better as `assets/`.

---

## Next steps, in the order that makes sense

1. **Name the folder**, move the two working documents in.
2. **Write engine tests.** There are none. `StarfieldEngine` is pure integer
   code with no AppKit, so it tests anywhere including a headless CI runner —
   projection, size ramp, respawn, clamps, and the LCG sequence against a fixed
   seed. This is the prerequisite that makes CI worth more than "it compiles".
3. **Make `build.sh` universal** — `ARCHS` and `MIN_MACOS` variables, two
   compile passes, `lipo`, and `LSMinimumSystemVersion` down to 13.0.
4. **`ci.yml`** — build, engine tests, SVG drift check, LoadTest.
5. **`release.yml`** — tag-triggered, zip, GitHub Release; unsigned at first.

---

## What to distrust

Claims in this repository that are reasoned but **not verified**:

- **Anything about macOS 13, 14, or 15.** Everything was built and run on
  macOS 26. macOS 14 restructured the screen saver host; this port has only
  ever run under the new arrangement.
- **Multi-monitor behavior** (`docs/NOTES.md` deviation 4). Follows from the
  recovered `GetSystemMetrics` calls on the Windows side and documented macOS
  behavior on the other, but this machine drove one display.
- **Whether AppKit view instantiation survives a headless CI runner.** Both
  `LoadTest` and `Render` construct an `NSView`. If they fail in CI, engine
  tests still cover the arithmetic that could actually regress.
- **GitHub runner labels**, which change; **whether `stapler` accepts a bare
  `.saver`**; **`.pkg` per-user install semantics**. All flagged in the plan.

Things that *were* verified are marked as such, with commands and output, in
`ci-and-distribution.md`'s appendix and throughout `docs/TEARDOWN.md`.

---

## Two corrections worth remembering

Both were stated wrongly earlier and are easy to repeat:

1. **The repository is private, not public.** This weakens the copyright
   caution about `docs/NOTES.md` — a private repo is not redistribution — and it
   means GitHub Actions minutes are billed, with macOS runners at 10×.
2. **The `14.0` deployment target in `build.sh` was arbitrary**, not
   researched. 13.0 is the real floor for a clean build; below that Swift wants
   back-deployment archives that ship arm64-only with Command Line Tools.

---

## Reproducing the teardown

The original binary is not in the repository. With your own copy at
`bin/ssstars.scr`:

```sh
python3 Tools/pe-imports.py bin/ssstars.scr          # the map: 90 imports
xcrun llvm-objdump -d --no-show-raw-insn bin/ssstars.scr > dis.txt
grep '100101c' dis.txt                               # PatBlt call sites
```

`docs/TEARDOWN.md` walks the rest. The UTF-16 string extractor is in its §2 — macOS
`strings` has no `-el`, which is why one is needed.
