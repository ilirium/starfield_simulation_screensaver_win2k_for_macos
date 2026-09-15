# Handoff

Where the project stands, what is decided, what is not, and what to distrust.
Updated 2026-09-15.

`CLAUDE.md` tells a new session how to work in the repo. This file is the
state of play.

### Starting cold

```sh
git branch --show-current     # expect: uninstaller-and-a-few-fixes
./build.sh                    # builds everything; 103 engine + 57 uninstaller checks, then LoadTest
```

If `build.sh` passes, the tree is healthy. It was clean and every change
committed when this was written.

**v1.1.0 is built and not yet released.** All five commits from
`aingineering/AING-0005-uninstaller-revised.md` §7 are done, with the
amendments from `aingineering/AING-0006-thumbnail-cache.md`. What remains is
landing and tagging — see "Landing v1.1.0" below. Nothing is mid-flight.

Read `CLAUDE.md` first, then `docs/NOTES.md` before touching
`Sources/StarfieldEngine.swift` — the integer math there is deliberately
faithful to a disassembled binary, and several things that look like defects
are not. `git log --first-parent main` is the short history; plain `git log`
is every step.

---

### Landing v1.1.0

Nothing is pushed by this project's convention; pushing is done by hand.

1. **Date the changelog.** `CHANGELOG.md`'s 1.1.0 heading says *unreleased*.
   Replace that with the release date at tag time, so it cannot go quietly
   stale if tagging slips.
2. **Merge to `main` with `--no-ff`**, so the branch's commits stay grouped as
   one piece of work rather than strung along main's first-parent path.
3. **Then tag.** Merge first, tag second: a tag is a claim that the commit is
   mainline state, and tagging a branch tip leaves the released commit
   unreachable from `main`.

```sh
git checkout main && git merge --no-ff uninstaller-and-a-few-fixes
git tag v1.1.0 && git push origin main v1.1.0
```

`release.yml` refuses to publish if the tag disagrees with
`CFBundleShortVersionString`, which is now **1.1.0** (`CFBundleVersion` 2).

**Run `git fetch` before comparing branches.** A stale remote-tracking ref made
local `main` look three commits ahead of `origin/main` during this work; after
a fetch both were `52855f9`. The divergence was not real, but the check is
still worth doing — an earlier version of this file claimed everything was
pushed when it was not.

---

### What v1.1.0 contains

Three features and a set of findings that changed two of them.

| | |
|---|---|
| **An uninstaller** | `uninstall.sh`, shipped inside the bundle, in the zip, and as raw commands in the README |
| **A preview thumbnail** | generated at build time by `Tools/Thumbnail` from the engine, committed nowhere |
| **A `Render` fix** | it no longer writes to a real settings store |

Full reasoning in AING-0005 and AING-0006; the narrative versions, with the
wrong turns, are `docs/UNINSTALLING.md` and `docs/THUMBNAIL.md`.

**Step 0 passed.** The `Contents/Resources/thumbnail.png` convention is still
honoured for third-party legacy savers on macOS 26.6.2 — and all 289
XScreenSaver bundles use it, which is independent precedent.

It nearly returned the wrong answer. The pane showed a generic swirl, which was
**a stale cache**, not a dead convention. Believing the tile would have
replanned the feature away.

Two findings came out of chasing that, and both are now implemented:

1. **A tile cache that nothing about the bundle invalidates** — not changed
   contents, not wholesale replacement, not a version bump; all three were
   tested. There is no supported invalidation call. Hence
   `./uninstall.sh --refresh-preview`, which **anyone upgrading from 1.0.0
   needs once** or the pane keeps showing the old tile. Documented in the
   README and in the generated release notes.
2. **The saver's real settings live in the sandbox container**, which
   `defaults -currentHost` cannot see. An uninstaller sweeping only the visible
   path deletes a decoy. `uninstall.sh` sweeps both. Homebrew's XScreenSaver
   uninstaller has this bug and left four orphans on this machine, so it is
   demonstrated rather than predicted.

The oracle for rechecking any of this without eyeballing a tile: a thumbnail
that was actually read produces a **180×116** cache entry; anything else lands
at **214×130**.

---

## What exists and works

A macOS screen saver reproducing the Windows 2000 "Starfield Simulation"
(`ssstars.scr`, 5.00.2195.6601). **Installed and confirmed working** on macOS
26.6.2, Apple Silicon.

```sh
./build.sh                                   # builds, tests, signs, self-verifies
cp -R build/Starfield.saver ~/Library/"Screen Savers"/
```

`build.sh` produces six things and runs three suites, so a broken build fails
loudly rather than at screen-blank time:

| | |
|---|---|
| `build/Starfield.saver` | the plugin, ad-hoc signed, arm64, macOS 13.0+; carries the thumbnails and the uninstaller |
| `build/StarfieldPreview` | the saver in a normal window; `[density] [warp]` |
| `build/Render` | offscreen PNG frames; `--svg docs/assets` regenerates the README art |
| `build/Thumbnail` | the two System Settings preview images; engine + CoreGraphics, no AppKit |
| `build/LoadTest` | loads a `.saver` as macOS does; non-zero exit on failure |
| `build/EngineTests` | 103 checks against the disassembly; no AppKit, runs headless |
| `Tools/uninstall-tests.sh` | 57 hermetic checks over `uninstall.sh` |

The step order matters: everything that ships inside the bundle is copied into
`Contents/Resources` **before** signing, and the seal is verified afterwards.
Adding a file to a signed bundle fails silently until macOS refuses to load it.

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
`CFBundleShortVersionString`. **v1.0.0 is published**, unsigned; **1.1.0 is
built and waiting to be tagged**.

The zip now stages an unversioned `Starfield/` folder holding the saver,
`uninstall.sh` and `Uninstall Starfield.command`. The round-trip check verifies
the signature, both executable bits and the three sealed resources survive
packing.

---

## Repository map

```
Sources/              engine (pure Int math), view (AppKit), config sheet, preview main
Tools/Render/         offscreen renderer + SVG generator
Tools/LoadTest/       bundle verification
Tools/EngineTests/    engine test suite, framework-free
Tools/Thumbnail/      System Settings preview images, engine + CoreGraphics only
Tools/uninstall-tests.sh  hermetic tests for uninstall.sh
Tools/pe-imports.py   PE import-table dumper, how the teardown started
Resources/            Info.plist (NSPrincipalClass = StarfieldView)
packaging/            "Uninstall Starfield.command", ships in the zip only
docs/                 the four technical documents
docs/assets/          the two README SVGs (generated, do not hand-edit)
aingineering/         working documents, AING-NNNN
.github/workflows/    ci.yml, release.yml
```

The root holds `README.md` (front page), `CHANGELOG.md` (what changed in each
release), this file, `CLAUDE.md` (which must stay there, by harness convention),
`LICENSE`, and `uninstall.sh`.

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
| `aingineering/README.md` | **index**: one line on each document, and which are superseded |
| `aingineering/AING-0001-ci-and-distribution.md` | CI, universal builds, signing, packaging — researched, now partly implemented |
| `aingineering/AING-0002-folder-naming-options.md` | the folder-naming long list, and the decision that came from outside it |
| `aingineering/AING-0003-uninstaller.md` | v1.1.0 plan, **superseded**. Kept as the record of what was first proposed |
| `aingineering/AING-0004-plan-review.md` | two independent reviews of AING-0003; 16 findings, 3 structural |
| `aingineering/AING-0005-uninstaller-revised.md` | the v1.1.0 plan, **implemented**. Supersedes AING-0003 |
| `aingineering/AING-0006-thumbnail-cache.md` | step 0's result and two gaps it uncovered, **implemented**; amends AING-0005 §1, §3, §4, §5 |
| `aingineering/AING-0007-applescript-uninstaller.md` | **the next plan**: a GUI uninstaller in AppleScript, for v1.2.0. Not started |

New working documents take the next `AING-NNNN` in sequence; numbers are never
reused, and a plan is never amended in place — a revision gets a new number.
Each document's own `Status:` line is therefore frozen at the time of writing;
`aingineering/README.md` carries the current state.

---

## Git state

v1.0.0 work is **merged into `main`**. The repository is **public**,
MIT-licensed, and `v1.0.0` is tagged and released.

Current work is on **`uninstaller-and-a-few-fixes`**, branched from `main` at
`52855f9`, ten commits ahead — **v1.1.0, complete and unreleased**:

```
e656c19  Write up the uninstaller and the thumbnail
0a460ec  Package the uninstaller, and add a changelog      <- plan commit 4
107189f  Generate the System Settings thumbnail, and reorder the build   <- 3
94483e9  Add the uninstaller, with tests                   <- 2
07f2319  Stop Render writing to the real settings store    <- 1
8c88476  Answer step 0, and record the two gaps it uncovered
41d7322  Correct where the step 0 evidence actually lives
e4c5b3b  Prepare the handoff for a fresh session
3cfee82  Revise the v1.1.0 plan as AING-0005
8a8c8f8  Review AING-0003 twice, independently
```

Plus this commit, which is AING-0005 §7's commit 5: the version bump to 1.1.0,
`CLAUDE.md`, and this file.

Note the v1.1.0 documents are split across `main` and the branch: AING-0003 and
the branch-name decision landed on `main` before the branch was cut; AING-0004
onwards are on the branch. Nothing is lost either way, but `main` alone shows a
superseded plan with no review and no revision beside it.

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

1. **Land and tag v1.1.0.** The work is done; see "Landing v1.1.0" above. Date
   the changelog, merge `--no-ff`, then tag.
2. **Build the AppleScript GUI uninstaller**, `AING-0007-applescript-uninstaller.md`.
   Three commits, for v1.2.0. Feasibility is measured and settled —
   `osacompile` needs no Xcode, the app ad-hoc signs like the saver, and its
   handlers can be tested headlessly. **Two decisions are open and must be made
   first**: §3, what the GUI does about `--all-users`, and §4, whether the app
   joins `Uninstall Starfield.command`, replaces it, or is not built at all.
   An independent review of the plan is wanted at implementation time.
3. **Run it on macOS 13, 14 and 15.** CI covers building and loading; it cannot
   cover a screen saver actually blanking a screen, and there is no runner
   image below 14. A VM is the realistic route.
4. **Decide the $99.** Everything in §4 and §5 of `AING-0001` waits on it, and
   nothing else does.
5. **Multi-monitor**, whenever a second display is to hand — the last untested
   claim that is purely about behavior rather than packaging.
6. **Watch what the first downloaders hit.** The Gatekeeper story is reasoned
   and partly verified — quarantine does propagate through the zip onto the
   inner executable — but nobody has yet installed a downloaded build on a
   machine that did not produce it.

---

## What to distrust

Claims in this repository that are reasoned but **not verified**:

- **Whether `defaults -currentHost delete` can reach the sandbox-container
  domain at all.** It cannot *read* it — `defaults -currentHost read
  com.ilirium.Starfield` returns the non-container values — but deletion was
  not tried. AING-0006 §7 depends on the answer: if it cannot, removal there is
  file-only, and the live-client ordering in AING-0005 §2.1 matters more.
- **How long a stale tile-cache entry survives on its own.** `/var/folders` is
  cleaned periodically, so the staleness is presumably not permanent, but the
  eviction interval was never measured. Do not lean on it.
- **What the 214×130 tiles actually are.** "Generic fallback" is the obvious
  reading and it is unproven — all ten are distinct images. Nothing in the plan
  depends on it; the 180×116 bucket is the oracle that matters.
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
