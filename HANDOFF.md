# Handoff

Where the project stands, what is decided, what is not, and what to distrust.
Updated 2026-09-15.

`CLAUDE.md` tells a new session how to work in the repo. This file is the
state of play.

### Starting cold

```sh
git branch --show-current     # expect: uninstaller-and-a-few-fixes
./build.sh                    # builds everything, runs 103 engine tests + LoadTest
```

If `build.sh` passes, v1.0.0 is healthy. The working tree was clean and every
change committed when this was written.

**v1.1.0 is planned but not started.** No code has been written for it — the
branch carries planning documents only. Implement
`aingineering/AING-0005-uninstaller-revised.md`; it is self-contained.

**One thing is mid-flight and needs a human, not a tool.** See "In-flight: step
0" below before building anything, because a modified bundle is installed on
this machine that `build.sh` did not produce.

Read `CLAUDE.md` first, then `docs/NOTES.md` before touching
`Sources/StarfieldEngine.swift` — the integer math there is deliberately
faithful to a disassembled binary, and several things that look like defects
are not. `git log --first-parent main` is the short history; plain `git log`
is every step.

---

### In-flight: step 0 of the v1.1.0 plan

AING-0005 §5 rests on an unconfirmed claim — that macOS still finds a saver's
preview image at `Contents/Resources/thumbnail.png`, a filename convention with
no `Info.plist` key, for *third-party* legacy savers. `Random.saver` does it
this way; it is Apple's own, and the convention predates System Settings.

Step 0 was set up and **the answer was never reported**:

- `build/Starfield.saver` and `~/Library/Screen Savers/Starfield.saver` both
  carry deliberately garish **magenta** test thumbnails (90×58 and 180×116,
  white bar across the middle), added by hand and re-signed.
- `legacyScreenSaver` was restarted so System Settings would re-read the bundle.

**To finish it:** open System Settings → Screen Saver, find Starfield, and see
which of these is true.

| Seen | Means |
|---|---|
| magenta rectangle with a white bar | convention works; §5 proceeds as planned |
| the previous generic fallback | convention is dead for third-party savers; §5 needs replanning |
| a live-animating starfield | System Settings renders live and ignores static thumbnails; also a replan |

**Then reconcile the machine**, because that installed bundle is out-of-band —
deliberate, uncommitted, and not reproducible from `build.sh` as it stands:

```sh
./build.sh && cp -R build/Starfield.saver ~/Library/"Screen Savers"/
```

What step 0 *did* already establish, and is worth keeping either way: adding
files to `Contents/Resources` invalidates the signature
(`codesign --verify` → "a sealed resource is missing or invalid"), and
re-signing seals them in. So AING-0005's build reorder is genuinely required,
not defensive.

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

Both workflows pin `actions/checkout` and `actions/upload-artifact` at **v7**;
v4 was warned off the deprecated Node 20 runtime during the first release run.

Releases are tag-triggered: `git tag v1.2.3 && git push origin v1.2.3` builds,
packs the bundle with `ditto`, re-verifies the *unpacked archive* rather than
the bundle that was never packed, and publishes with generated install notes
and a checksum. It refuses to publish if the tag disagrees with
`CFBundleShortVersionString`. **v1.0.0 is published**, unsigned.

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
.github/workflows/    ci.yml, release.yml
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
| `aingineering/AING-0003-uninstaller.md` | v1.1.0 plan, **superseded**. Kept as the record of what was first proposed |
| `aingineering/AING-0004-plan-review.md` | two independent reviews of AING-0003; 16 findings, 3 structural |
| `aingineering/AING-0005-uninstaller-revised.md` | **the plan to implement.** Self-contained; supersedes AING-0003 |

New working documents take the next `AING-NNNN` in sequence; numbers are never
reused.

---

## Git state

v1.0.0 work is **merged into `main`**. The repository is **public**,
MIT-licensed, and `v1.0.0` is tagged and released.

Current work is on **`uninstaller-and-a-few-fixes`**, branched from `main` at
`52855f9`, two commits ahead — **planning documents only, no code**:

```
3cfee82  Revise the v1.1.0 plan as AING-0005
8a8c8f8  Review AING-0003 twice, independently
```

Note the v1.1.0 documents are split across both: AING-0003 and the branch-name
decision landed on `main` before the branch was cut; AING-0004 and AING-0005 are
on the branch. Nothing is lost either way, but `main` alone shows a superseded
plan with no review and no revision beside it.

Tip of `main` is `52855f9`; `v1.0.0` is tagged at `1e6d304`. Shape:

```
* 52855f9  Name the v1.1.0 branch              <- main, and the branch point
* fd75db8  thumbnail + branch strategy in AING-0003
* 12cbd24  Plan the uninstaller as AING-0003
* 5003ca4  Prepare the handoff for a fresh session
* 23dbd49  Record the 1.0.0 release
* 00101f3  Bump the actions off the deprecated Node 20 runtime
* 1e6d304  Correct how the branch landed       <- v1.0.0 tag
*   d63fcab  Merge the macOS port
|\
| * 741b4ad  release automation + install instructions
| * (eleven commits of the port, its docs, tests and CI)
|/
* 56cc1f7  MIT License
* 0069a37  Initial commit
```

`macos-port` still exists and points at `741b4ad`, inside the merge. It can be
deleted, or reused — new work is cleaner on a fresh branch off `main`.

**Landed on `main`** on 2026-09-15 via a `--no-ff` merge commit, so the branch
commits stay grouped as one piece of work rather than strung along main's
first-parent path. `git log --first-parent main` reads as a list of what
landed; plain `git log` still shows every step.

It was briefly fast-forwarded first. Rebuilding it as a merge needed no force
push and rewrote nothing: rewinding local `main` to the licence commit and
merging `--no-ff` produces a merge commit whose second parent *is* the old
fast-forwarded tip, so it descends from what was already published and pushes
as an ordinary fast-forward. Worth remembering — undoing a fast-forward is
usually assumed to require a force push, and here it did not.

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

That is now the only thing blocking anything. `release.yml` shipped unsigned
rather than waiting on it, which was the right call — the workaround is one
`xattr` command, documented in the README and in every release's notes.

---

## Next steps, in the order that makes sense

1. **Build v1.1.0** — an uninstaller, a System Settings preview thumbnail, and
   a fix for `Render` overwriting the user's real saved settings. Every design
   question is answered; it needs implementing, not deciding. Work on the branch
   `uninstaller-and-a-few-fixes`, off `main`.

   **Implement `AING-0005-uninstaller-revised.md`** — it is self-contained and
   supersedes AING-0003. Read AING-0004 only for why the plan changed.

   Start with its step 0 (§7): confirm macOS still honours the
   `Contents/Resources/thumbnail.png` convention for third-party savers. §5
   rests entirely on it and it is a five-minute check needing a human to look
   at the Screen Saver pane.
2. **Run it on macOS 13, 14 and 15.** CI covers building and loading; it cannot
   cover a screen saver actually blanking a screen, and there is no runner
   image below 14. A VM is the realistic route.
3. **Decide the $99.** Everything in §4 and §5 of `AING-0001` waits on it, and
   nothing else does.
4. **Multi-monitor**, whenever a second display is to hand — the last untested
   claim that is purely about behavior rather than packaging.
5. **Watch what the first downloaders hit.** The Gatekeeper story is reasoned
   and partly verified — quarantine does propagate through the zip onto the
   inner executable — but nobody has yet installed a downloaded build on a
   machine that did not produce it.

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
