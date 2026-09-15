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

CI runs all of this on every push and pull request across `macos-14`,
`macos-15` and `macos-latest`. **All six jobs pass**, in about 55 seconds.

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

Work is on **`macos-port`**, twelve commits, rebased onto `main` so history is
linear. The repository is **public** and MIT-licensed.

```
(this one) CI results recorded
9b52180  handoff brought up to date
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

**Landed on `main`** on 2026-09-15 by fast-forward, so `main` and `macos-port`
point at the same commit and the history is a straight line from the initial
commit.

Getting there needed one repair. Committing `LICENSE` to `main` alone had
diverged the branches, and `git merge --ff-only` fails across a divergence —
so the landing instruction this file used to give had quietly stopped working.
Rebasing `macos-port` onto `origin/main` restored it, at the cost of one
force-push.

Everything is pushed. CI has run green on the branch — see below.

One trap worth naming, because it cost a failed push: committing to `main` on
GitHub (the licence, the description) moves `origin/main` without moving the
local ref. A later `git push --all` then drags that stale `main` into the push
and the whole command fails, even though the branch it was actually meant to
carry went up fine. `git push` alone pushes only the current branch. If local
`main` does fall behind, `git branch -f main origin/main` is the whole fix.

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

1. **`release.yml`**, unsigned — tag-triggered, zip the `.saver`, create a
   GitHub Release. The one piece of `AING-0001` that was planned and not built.
2. **Run it on macOS 13, 14 and 15.** CI covers building and loading; it cannot
   cover a screen saver actually blanking a screen, and there is no runner
   image below 14. A VM is the realistic route.
3. **Decide the $99.** Everything in §4 and §5 of `AING-0001` waits on it, and
   nothing else does.
4. **Multi-monitor**, whenever a second display is to hand — the last untested
   claim that is purely about behavior rather than packaging.

---

## What to distrust

Claims in this repository that are reasoned but **not verified**:

- **Whether the saver actually *runs* on macOS 13, 14 or 15.** CI now builds
  and loads it on 14, 15 and latest, which is a real narrowing of this gap —
  but loading a bundle is not running a screen saver. macOS 14 restructured the
  screen saver host, and nothing has exercised the pre-14 arrangement at all.
  Everything was developed on macOS 26. There is no CI image below 14, so this
  needs a real machine or a VM.
- **Multi-monitor behavior** (`docs/NOTES.md` deviation 4). Follows from the
  recovered `GetSystemMetrics` calls on the Windows side and documented macOS
  behavior on the other, but this machine drove one display.
- **Whether `stapler` accepts a bare `.saver`**, and **`.pkg` per-user install
  semantics**. Both flagged in `AING-0001`, both blocked on the signing
  decision anyway.

Things that *were* verified are marked as such, with commands and output, in
`AING-0001`'s appendix and throughout `docs/TEARDOWN.md`.

### Resolved by the first CI run (2026-09-15)

Two long-standing entries above came off this list, and one is worth stating
plainly because it was the biggest unknown in the project:

- **AppKit view instantiation works fine on a headless runner.** `LoadTest`
  resolved `NSPrincipalClass` through the Objective-C runtime, instantiated a
  `ScreenSaverView` and ran a frame on all three images; `Render` produced its
  offscreen frames and regenerated the SVGs with no drift. No window server was
  needed. Splitting `ci.yml` into an engine job and a build job was insurance
  against a failure that did not happen — worth keeping, since it costs nothing
  and the arithmetic gate stays independent, but the worry itself is settled.
- **The runner labels `macos-14`, `macos-15` and `macos-latest` all exist and
  all work.** True as of 2026-09-15; these do change over time, so a future
  failure of the whole matrix at once is most likely a retired image rather
  than a real regression.

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
