# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS port of the Windows 2000 "Starfield Simulation" screen saver.

The original is `bin/ssstars.scr`: a 33 KB stripped PE32 x86 binary,
`ssstars`, FileVersion 5.00.2195.6601. It is the reference implementation, not
a build input — it cannot run on macOS, and nothing in the build reads it.

**It is deliberately not committed** (`.gitignore`), so a fresh clone will not
have it. Nothing here needs it; supply your own copy from a Windows 2000
`system32` only if you want to re-check the disassembly against docs/NOTES.md.

The documentation set, in the order a newcomer should read it:

| File | What it is |
|---|---|
| `docs/WIN32-PRIMER.md` | How the original works and how Win32 works; assumes no Windows background |
| `docs/TEARDOWN.md` | How the binary was disassembled, including two wrong turns |
| `docs/HOW-IT-WORKS.md` | How the Swift port works, for readers new to Swift/AppKit |
| `docs/NOTES.md` | Bare reference: every constant with the address it came from |
| `docs/UNINSTALLING.md` | Removing a saver on modern macOS: the three caches, and the sandbox container |
| `docs/THUMBNAIL.md` | The preview image, and the validation experiment that lied |

Design notes, research and plans live in `aingineering/`, indexed by
`aingineering/README.md`. Plans are never amended in place — a revision gets
the next `AING-NNNN` — so each document's own `Status:` line reflects when it
was written, not now.

`docs/NOTES.md` records the disassembly: every constant in `StarfieldEngine.swift`
is annotated there with the address it came from. **Read docs/NOTES.md before
changing anything in the engine** — the integer math, the truncating division,
the clamps, and the odd placement of the speed ramp inside the per-star loop
are all deliberate fidelity choices, not defects to clean up. docs/NOTES.md also
lists the three places the port knowingly departs from the original.

## Build

Command Line Tools are sufficient; full Xcode is not installed and
`xcodebuild` is unavailable. There is no Xcode project and no package manifest
— `build.sh` drives `swiftc`/`clang` directly.

```sh
./build.sh                          # -> build/Starfield.saver and build/StarfieldPreview
```

A `.saver` is an `MH_BUNDLE`, which `swiftc` will not emit directly, so the
build compiles to a single object with `-wmo` and links it with
`clang -bundle`. Dropping `-wmo` breaks the build ("cannot specify -o when
generating multiple output files"). The bundle is ad-hoc signed (`codesign -s -`);
it will not load unsigned.

**The order of steps in `build.sh` is load-bearing.** The signature seals
`Contents/Resources`, so everything that ships inside the bundle — the
thumbnails and `uninstall.sh` — must be copied in *before* `codesign` runs.
Adding a file afterwards gives "a sealed resource is missing or invalid", and
nothing says so until macOS refuses to load the plugin. The build verifies the
seal with `codesign --verify --deep --strict` immediately after signing, and
asserts the thumbnail dimensions before it, because both failures are otherwise
silent. See `docs/THUMBNAIL.md` §10.

## Running and verifying

`Sources/main.swift` is the standalone harness and is **not** part of the
`.saver` — it is compiled only into `StarfieldPreview`. The shared sources are
the other three files in `Sources/`.

```sh
./build/StarfieldPreview 120 8      # density, warpSpeed; opens a real window
```

`build.sh` also builds four tools and runs three test suites:

- `build/EngineTests` checks `StarfieldEngine` against the disassembly — the
  LCG sequence, truncating projection, the size ramp, the clamps, and the
  speed ramp's placement inside the per-star loop. Each section names the
  `docs/NOTES.md` address it verifies, so a failure points at the constant that
  drifted. It links `StarfieldEngine.swift` **alone**, with no Cocoa and no
  ScreenSaver, so it runs headless. `build.sh` runs it before `LoadTest`:
  a fidelity regression is more specific than "the plugin would not load".
- `build/LoadTest <path.saver>` loads the bundle the way macOS does — resolves
  `NSPrincipalClass` by name, instantiates, runs a frame. `build.sh` runs it on
  every build, so a broken bundle fails the build rather than failing silently
  at screen-blank time. It exits non-zero on failure, so it works as a CI gate.
- `build/Render <out-dir> [--svg docs/assets]` renders frames offscreen via
  `cacheDisplay(in:to:)` (`single.png`, plus a `trails.png` max-composite), and
  with `--svg` regenerates the two README images. It drives the view against a
  **scratch** defaults domain, injected through `ScreenSaverDefaultsStore`, so
  regenerating artwork cannot overwrite saved settings. Do not reintroduce a
  `?? .standard` fallback there: it silently restores that bug.
- `build/Thumbnail <out-dir>` writes `thumbnail.png` (90x58) and
  `thumbnail@2x.png` (180x116), the images System Settings shows in the Screen
  Saver pane. It links `StarfieldEngine.swift` **alone** plus CoreGraphics and
  ImageIO — no AppKit — so producing the shipped bundle never depends on a
  window server. Fixed seed, so the bundle is reproducible; the images are
  generated into `build/` and committed nowhere.
- `Tools/uninstall-tests.sh` exercises `uninstall.sh`. Hermetic through
  directory overrides rather than a throwaway `HOME`, because `cfprefsd`
  ignores `HOME` — see `docs/UNINSTALLING.md` §7 before changing it, since the
  obvious design deletes the developer's real preferences.

The SVGs are emitted from `StarfieldEngine` with **fixed seeds**, so they
regenerate byte-for-byte. Keep it that way: it is what lets CI diff them and
catch artwork drifting from the simulation. Regenerate after any change to the
engine. (SVG needs no Y flip: like Windows GDI it measures Y downward. The
macOS view is the odd one out.)

The trail image is the useful visual regression check: stars must streak
radially outward from the center and grow along the way.

`Tools/pe-imports.py <binary>` dumps a 32-bit PE import table with each
function's IAT address — the address to grep a disassembly for to find that
function's call sites. It is how the teardown started; see `docs/TEARDOWN.md`
§3.

Prefer these over screen capture — verifying visuals does not require
recording the user's display.

## CI

`.github/workflows/ci.yml` runs on every push and pull request, across
`macos-14`, `macos-15` and `macos-latest`. Two jobs, deliberately separate:

- **engine** compiles `StarfieldEngine.swift` plus the test suite directly and
  runs it. No frameworks, so it needs nothing from a window server. It reads
  `MIN_MACOS` out of `build.sh` rather than repeating it.
- **build** runs `./build.sh`, inspects the bundle, and regenerates the SVGs to
  check they still match the simulation.

They are split so the arithmetic signal stays readable even if AppKit turns out
not to work on a headless runner — which is untested, and is what the build job
is there to find out.

## Installing

```sh
cp -R build/Starfield.saver ~/Library/"Screen Savers"/
```

Then pick it in System Settings > Screen Saver. On macOS 14+ savers run inside
`legacyScreenSaver`, so a crash shows up as that process failing, not this
bundle.

## Settings

Stored via `ScreenSaverDefaults(forModuleWithName: "com.ilirium.Starfield")`,
under the original's key names `Density` (10-200, default 25) and `WarpSpeed`
(0-10, default 5). `ConfigController` and `StarfieldView` both talk to the
`ScreenSaverDefaultsStore` protocol rather than `ScreenSaverDefaults` directly,
so the preview harness can pass plain `UserDefaults` and `Render` can pass a
scratch domain.

**That name resolves to two different files, and which one you get depends on
who is asking.** Screen savers are sandboxed, so the installed saver reads and
writes inside the host's container:

```
~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost/
```

while unsandboxed tools — `StarfieldPreview`, `Render`, `defaults` — land in
the plain `~/Library/Preferences/ByHost/`. The two hold independent values.
`defaults -currentHost read com.ilirium.Starfield` **cannot see the container
copy at all**, so it is a misleading way to check what the saver is actually
using; read the container plist directly.

This matters for anything that deletes: `uninstall.sh` sweeps both, and an
uninstaller that sweeps only the visible one leaves the user's real settings
behind. `docs/UNINSTALLING.md` §4 has the measurements.

## Uninstalling

`uninstall.sh` lives in the repository root, is committed `100755`, and is
copied into `Contents/Resources` by `build.sh` so it travels with an install.
`Tools/uninstall-tests.sh` runs on every build.

`--refresh-preview` clears the System Settings tile cache. It exists because
that cache is keyed per module and **nothing about the bundle invalidates it** —
not changed contents, not wholesale replacement, not a version bump. Anyone
upgrading from an earlier version needs it once, or the pane keeps showing the
old thumbnail. A plain uninstall deliberately does not clear it.

Verifying the thumbnail does not need a screenshot: a thumbnail that was
actually read produces a **180x116** entry in that cache, and anything else
lands at 214x130.
