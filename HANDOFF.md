# Handoff

Where the project stands, what is decided, what is not, and what to distrust.
Updated 2026-09-15.

`CLAUDE.md` tells a new session how to work in the repo. This file is the
state of play.

---

## What exists and works

A macOS screen saver reproducing the Windows 2000 "Starfield Simulation"
(`ssstars.scr`, 5.00.2195.6601). **Installed and confirmed working** on macOS
26.6.2, Apple Silicon.

```sh
./build.sh                                   # builds, tests, signs, self-verifies
cp -R build/Starfield.saver ~/Library/"Screen Savers"/
```

`build.sh` produces five things and runs two of them, so a broken build fails
loudly rather than at screen-blank time:

| | |
|---|---|
| `build/Starfield.saver` | the plugin, ad-hoc signed, arm64, macOS 13.0+ |
| `build/StarfieldPreview` | the saver in a normal window; `[density] [warp]` |
| `build/Render` | offscreen PNG frames; `--svg docs/assets` regenerates the README art |
| `build/LoadTest` | loads a `.saver` as macOS does; non-zero exit on failure |
| `build/EngineTests` | 103 checks against the disassembly; no AppKit, runs headless |

Command Line Tools are sufficient. There is no Xcode project, no package
manifest, no dependencies.

---

## Repository map

```
Sources/              engine (pure Int math), view (AppKit), config sheet, preview main
Tools/Render/         offscreen renderer + SVG generator
Tools/LoadTest/       bundle verification
Tools/EngineTests/    engine test suite, framework-free
Tools/pe-imports.py   PE import-table dumper, how the teardown started
Resources/            Info.plist (NSPrincipalClass = StarfieldView)
docs/                 the four technical documents
docs/assets/          the two README SVGs (generated, do not hand-edit)
aingineering/         working documents, AING-NNNN
.github/workflows/    ci.yml
```

The root holds `README.md` (front page), this file, `CLAUDE.md` (which must
stay there, by harness convention) and `LICENSE`.

Documentation, in reading order:

| | |
|---|---|
| `README.md` | front page: install, build, settings, licence scope, pointers |
| `docs/WIN32-PRIMER.md` | how the original and Win32 work; assumes no Windows background |
| `docs/TEARDOWN.md` | how the binary was disassembled, including the wrong turns |
| `docs/HOW-IT-WORKS.md` | how the Swift port works; assumes no Swift/AppKit/ObjC |
| `docs/NOTES.md` | bare reference: every constant with its address |

Working documents:

| | |
|---|---|
| `aingineering/AING-0001-ci-and-distribution.md` | CI, universal builds, signing, packaging — researched, now partly implemented |
| `aingineering/AING-0002-folder-naming-options.md` | the folder-naming long list, and the decision that came from outside it |

New working documents take the next `AING-NNNN` in sequence; numbers are never
reused.

---

## Git state

Work is on **`macos-port`**, eleven commits, rebased onto `main` so history is
linear. The repository is **public** and MIT-licensed.

```
(this one) handoff brought up to date
545bb68  CI: engine tests and build, across three runner images
7cfa8e2  deployment floor 13.0, ARCHS and MIN_MACOS
413c726  engine tests
19c3948  docs/, docs/assets/, aingineering/
d7ea017  handoff, tool rescue, reproducible artwork
3344a4e  CI and distribution research, folder naming options
b48b4fe  the third GDI import, and a real README
2da4cc8  Win32 primer
b2aba45  teardown and port documentation
5ad0262  the port itself
56cc1f7  MIT License          <- was on main alone
```

To land it: `git checkout main && git merge --ff-only macos-port && git push`.

That command had **stopped working**: committing `LICENSE` to `main` alone
diverged the branches, and `--ff-only` fails across a divergence. Rebasing
`macos-port` onto `origin/main` restored it, at the cost of one force-push.

The five newest commits are **local and unpushed** by choice, pending review.
CI cannot report anything until they are pushed.

`bin/ssstars.scr` is gitignored and is Microsoft's; nothing in the build reads
it. `README.md` now carries a licence scope note saying so explicitly.

---

## Decisions already made

- **Source only, no binaries committed.** `build/` is gitignored. The README
  illustrations are SVG specifically so they stay text and can be diffed.
- **Fidelity over modernisation.** Truncating integer division, the speed ramp
  inside the per-star loop, the MSVC LCG — all reproduced on purpose.
  `docs/NOTES.md` lists the four deliberate deviations. Do not "fix" these.
  The engine tests now enforce it: hoisting the speed ramp out of the per-star
  loop fails the suite by design, with a message saying why.
- **20 fps**, matching the original's 50 ms timer. A smooth-motion mode was
  offered and not taken up; it remains available if wanted.
- **arm64-only, macOS 13.0 floor.** 13.0 is the researched floor for a clean
  link. `ARCHS` is an array and `lipo` runs unconditionally, so going universal
  is one word — verified by toggling it and checking both slices came out at
  `minos 13.0`.
- **Public repository, MIT**, as of 2026-09-15. Actions minutes are therefore
  free, and `ci.yml` is deliberately unfrugal as a result.
- **Tests before CI.** Written first, so the workflow gates on behavior rather
  than on compilation.
- **`aingineering/` for working documents**, `AING-NNNN` prefixes, flat.
- **No `Claude-Session` trailer** in commits. Turned off in
  `~/.claude/settings.json` via `attribution.sessionUrl: false`;
  `Co-Authored-By` was kept.

---

## Open decisions

**The $99/year Apple Developer Program.** Deferred, not refused. Until it is
paid, releases ship unsigned, and installing means the right-click-Open dance.
`AING-0001` §4 and §5 are written but unimplemented.

**`release.yml`.** Planned and not built — tag-triggered, zip the `.saver`,
create a GitHub Release. Left out deliberately, because its shape depends on
the signing question above. Unsigned is a perfectly good first version.

---

## Next steps, in the order that makes sense

1. **Push and watch CI.** Five commits are sitting local. The first run is an
   experiment, not a formality — see "what to distrust".
2. **Land `macos-port`.** `--ff-only` works again.
3. **`release.yml`**, unsigned, if a release is wanted before the $99 decision.
4. **Test on macOS 13, 14 and 15.** CI covers building and loading. Whether the
   saver actually *runs* under the pre-14 screen saver host still needs a real
   machine or a VM.

---

## What to distrust

Claims in this repository that are reasoned but **not verified**:

- **Anything about macOS 13, 14, or 15.** Everything was built and run on
  macOS 26. macOS 14 restructured the screen saver host; this port has only
  ever run under the new arrangement. The CI matrix starts closing this gap for
  build-and-load, and not at all for actual screen-saver behavior.
- **Multi-monitor behavior** (`docs/NOTES.md` deviation 4). Follows from the
  recovered `GetSystemMetrics` calls on the Windows side and documented macOS
  behavior on the other, but this machine drove one display.
- **Whether AppKit view instantiation survives a headless CI runner.** Still
  open — but now actively tested rather than worried about. The `build` job
  exercises it, and the `engine` job is deliberately independent of it so the
  arithmetic stays measurable whichever way it goes.
- **GitHub runner labels**, which change; **whether `stapler` accepts a bare
  `.saver`**; **`.pkg` per-user install semantics**. All flagged in `AING-0001`.

Things that *were* verified are marked as such, with commands and output, in
`AING-0001`'s appendix and throughout `docs/TEARDOWN.md`.

---

## Two things worth remembering

Both came out of writing the engine tests, and neither was obvious.

1. **The drawn size range is 1–4, not 1–5.** `docs/NOTES.md` gives the formula
   `(2560 - z) / 640 + 1`, whose ceiling is 5 — but reaching it needs `z == 0`,
   and `project()` cannot be called at `z == 0` at all, because the perspective
   divide traps before the size term is reached. The original has the same
   property. NOTES describes the formula's range; 1–4 is what gets drawn.

2. **Respawning at `z == 0` is load-bearing.** Clamping `z` to 1 instead looks
   equivalent and very nearly is: a star at `z == 1` projects far off screen and
   is recycled a line later anyway. The exception is a star on the exact centre
   ray, where `x` and `y` are both zero — its projection stays at the screen
   centre however small `z` gets, so clamping pins it there permanently. This
   mutation survived the first version of the test suite, and it needs an 8×8
   frame to observe at all: at 1024×768 the case arises roughly once in 786,432
   respawns, so a full-size run never reaches the branch.

---

## Reproducing the teardown

The original binary is not in the repository. With your own copy at
`bin/ssstars.scr`:

```sh
python3 Tools/pe-imports.py bin/ssstars.scr          # the map: 90 imports
xcrun llvm-objdump -d --no-show-raw-insn bin/ssstars.scr > dis.txt
grep '100101c' dis.txt                               # PatBlt call sites
```

`docs/TEARDOWN.md` walks the rest. The UTF-16 string extractor is in its §2 —
macOS `strings` has no `-el`, which is why one is needed.
