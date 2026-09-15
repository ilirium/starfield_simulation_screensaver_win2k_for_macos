# Changelog

A macOS port of the Windows 2000 "Starfield Simulation" screen saver.

Versions follow [semantic versioning](https://semver.org/). Dates are the
release date. Each entry says what changed and, where it is not obvious, why —
the reasoning usually lives in `aingineering/AING-NNNN`, which is linked rather
than repeated.

## [Unreleased]

### Added

- **An AI disclosure section in the README.** The port was written with heavy
  AI assistance and a human leading the ideas, decisions, testing and
  debugging; that is stated plainly rather than left to be inferred. It names
  the failures as well as the division of labour, because the repository's
  habits — label what was measured, record the wrong turns, mutation-test the
  suites, keep a distrust list — exist as a response to them.

### Verified

- **The 1.0.0 → 1.1.0 upgrade path, on a real machine.** `--refresh-preview`
  fixes a genuinely stale preview tile, and `uninstall.sh` works against a real
  install outside hermetic mode. Both had been tested only with fixtures and
  colour-swapped placeholders until now.

## [1.1.0] — 2026-09-15

An uninstaller, a Screen Saver pane preview, and a settings fix — plus two
findings about macOS that reshaped the first two.

### Added

- **An uninstaller**, `uninstall.sh`. It ships **inside** the installed bundle
  at `Contents/Resources/`, so it is still available long after the download
  has been deleted, and again in the release zip beside the saver, with an
  `Uninstall Starfield.command` wrapper for people who would rather not open a
  terminal. Flags: `--dry-run`, `--keep-settings`, `--all-users`,
  `--refresh-preview`, `-y`.

  It removes preferences from the **sandbox container** as well as the plain
  ByHost directory. Screen savers have been sandboxed since macOS 10.15, and
  the container copy is the one the running saver reads; `defaults
  -currentHost` cannot see it. Removing only the visible copy leaves the user's
  real settings behind — a bug Homebrew's XScreenSaver uninstaller has, and one
  the original plan for this uninstaller would have shipped.

- **A System Settings preview thumbnail.** The bundle previously shipped no
  preview image, so the Screen Saver pane showed a generic tile. Both sizes are
  generated at build time by `Tools/Thumbnail` from `StarfieldEngine` with a
  fixed seed — never hand-drawn, and committed nowhere.

- **`--refresh-preview`**, because System Settings caches those tiles per saver
  and *nothing* about replacing a bundle invalidates the cache — not changed
  contents, not wholesale replacement, not a version bump. All three were
  tested. There is no supported invalidation call, so clearing the cache
  directory is the only lever, and anyone upgrading from 1.0.0 needs it once.

- **Tests for the uninstaller**, `Tools/uninstall-tests.sh`, run by `build.sh`
  on every build. Hermetic through directory overrides rather than a throwaway
  `HOME`, because `cfprefsd` ignores `HOME` — the obvious design would delete
  the developer's real preferences while reporting success.

- **This changelog.**

### Changed

- **`build.sh` assembles `Contents/Resources` before signing**, not after. The
  signature seals that directory; adding a file afterwards fails with "a sealed
  resource is missing or invalid" and the failure is silent until macOS refuses
  to load the plugin. The build now also runs `codesign --verify --deep
  --strict`, so the seal is proved rather than assumed.

- **The release zip stages an unversioned `Starfield/` folder** holding the
  saver, `uninstall.sh` and the `.command` wrapper. The version stays in the
  archive filename, where it does not go stale in every instruction that tells
  someone which directory to `cd` into.

### Fixed

- **`Tools/Render` no longer writes to the real settings store.** Regenerating
  the README artwork used to set `Density` and `WarpSpeed` in the store the
  preview harness reads, silently replacing whatever had been chosen. It now
  uses a scratch domain, injected through the `ScreenSaverDefaultsStore`
  protocol the repository already had.

  Scope worth stating precisely: this only ever affected the preview harness.
  The installed saver reads its container copy, which was never touched.

### Notes

The full reasoning, including what was measured and what remains unverified, is
in [AING-0005](aingineering/AING-0005-uninstaller-revised.md) and
[AING-0006](aingineering/AING-0006-thumbnail-cache.md).

## [1.0.0] — 2026-09-15

First release. A working macOS screen saver reproducing the original's
behaviour, with the disassembly that justifies it written down.

### Added

- **The saver itself** — `StarfieldEngine` in pure integer arithmetic,
  an AppKit `ScreenSaverView`, and a rebuild of the original's
  "Starfield Simulation Setup" dialog. Settings use the original's key names,
  `Density` (10–200) and `WarpSpeed` (0–10).

- **Fidelity to the disassembled original**, deliberately. Truncating integer
  division, the MSVC LCG, the speed ramp's odd placement inside the per-star
  loop, and the clamps are all reproduced rather than modernised. Every
  constant is annotated in `docs/NOTES.md` with the address it came from, and
  the four knowing deviations are listed there too.

- **An engine test suite**, `Tools/EngineTests` — 103 checks against the
  disassembly, linking `StarfieldEngine` alone so it runs headless. Hoisting
  the speed ramp out of the per-star loop fails the suite by design.

- **`Tools/LoadTest`**, which loads a `.saver` the way macOS does — resolving
  `NSPrincipalClass` by name, instantiating, running a frame — so a broken
  bundle fails the build rather than failing at screen-blank time.

- **`Tools/Render`**, offscreen PNG frames plus the two README SVGs, generated
  from the engine with fixed seeds so CI can diff them and catch artwork
  drifting from the simulation.

- **`Tools/pe-imports.py`**, a 32-bit PE import-table dumper. It is how the
  teardown started.

- **Documentation** for readers with no Windows, Swift or AppKit background:
  `docs/WIN32-PRIMER.md`, `docs/TEARDOWN.md` (including two wrong turns),
  `docs/HOW-IT-WORKS.md`, and `docs/NOTES.md`.

- **CI**, across `macos-14`, `macos-15` and `macos-latest`, split into an
  engine job that needs no frameworks and a build job that exercises AppKit.

- **Tag-triggered releases**, which refuse to publish if the tag disagrees with
  `CFBundleShortVersionString`, and verify the *unpacked archive* rather than
  the bundle that was never packed.

### Known limitations

- **Ad-hoc signed, not notarized.** Notarization needs the $99/year Apple
  Developer Program, deliberately deferred. A downloaded build is quarantined;
  `xattr -dr com.apple.quarantine` is the documented workaround.
- **arm64 only**, macOS 13.0 or later. Going universal is one word in
  `build.sh` — `ARCHS` is an array and `lipo` already runs unconditionally.
- **Not run on macOS 13, 14 or 15.** CI builds and loads it there; loading a
  bundle is not running a screen saver, and everything was developed on 26.
- **Multi-monitor behaviour is untested.**
- **No preview thumbnail** in the Screen Saver pane. Fixed in 1.1.0.

[Unreleased]: https://github.com/ilirium/starfield_simulation_screensaver_win2k_for_macos/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/ilirium/starfield_simulation_screensaver_win2k_for_macos/releases/tag/v1.1.0
[1.0.0]: https://github.com/ilirium/starfield_simulation_screensaver_win2k_for_macos/releases/tag/v1.0.0
