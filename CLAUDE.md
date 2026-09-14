# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS port of the Windows 2000 "Starfield Simulation" screen saver.

The original is `bin/ssstars.scr`: a 33 KB stripped PE32 x86 binary,
`ssstars`, FileVersion 5.00.2195.6601. It is the reference implementation, not
a build input — it cannot run on macOS, and nothing in the build reads it.

**It is deliberately not committed** (`.gitignore`), so a fresh clone will not
have it. Nothing here needs it; supply your own copy from a Windows 2000
`system32` only if you want to re-check the disassembly against NOTES.md.

`NOTES.md` records the disassembly: every constant in `StarfieldEngine.swift`
is annotated there with the address it came from. **Read NOTES.md before
changing anything in the engine** — the integer math, the truncating division,
the clamps, and the odd placement of the speed ramp inside the per-star loop
are all deliberate fidelity choices, not defects to clean up. NOTES.md also
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

## Running and verifying

`Sources/main.swift` is the standalone harness and is **not** part of the
`.saver` — it is compiled only into `StarfieldPreview`. The shared sources are
the other three files in `Sources/`.

```sh
./build/StarfieldPreview 120 8      # density, warpSpeed; opens a real window
```

`Tools/main.swift` renders frames offscreen via `cacheDisplay(in:to:)` and
writes `single.png` plus a `trails.png` max-composite. The trail image is the
useful regression check: stars must streak radially outward from the center
and grow along the way. Build it the same way as the preview, substituting
`Tools/main.swift` for `Sources/main.swift`.

Prefer these over screen capture — verifying visuals does not require
recording the user's display.

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
(0-10, default 5). The preview harness writes to the same store, so the two
share state. `ConfigController` talks to the `ScreenSaverDefaultsStore`
protocol rather than `ScreenSaverDefaults` directly so the harness can pass
plain `UserDefaults`.
