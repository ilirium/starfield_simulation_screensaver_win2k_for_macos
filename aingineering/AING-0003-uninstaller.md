# Plan: an uninstaller, shipped as v1.1.0

Status: **decided, not implemented.** Every question below has an answer; no
code has been written. Written 2026-09-15, against `main` at `5003ca4`.

The four design questions were put and answered before planning went further;
the answers are in "Decisions taken". Everything in "What an install leaves
behind" and "Constraints" was measured on this machine, not reasoned about —
commands are given so it can be rechecked when macOS changes.

---

## 0. Why

There is no uninstaller and no documentation for removing the saver. The
footprint is small, but it is fiddly in three ways that make a hand-written
`rm` likely to be incomplete:

- The preferences file is **ByHost**, named with a hardware UUID, so it cannot
  be typed from memory and a home directory that has moved between Macs carries
  one per machine.
- There are **two** install locations, and the all-users one needs `sudo`.
- Removing a saver that is **currently selected** leaves macOS pointing at
  something that is gone.

---

## 1. What an install leaves behind

Measured, not assumed:

| Path | On this machine |
|---|---|
| `~/Library/Screen Savers/Starfield.saver` | present |
| `/Library/Screen Savers/Starfield.saver` | absent (never created by our README) |
| `~/Library/Preferences/ByHost/com.ilirium.Starfield.<UUID>.plist` | present |

The preferences file held exactly what it should:

```
$ plutil -p ~/Library/Preferences/ByHost/com.ilirium.Starfield.*.plist
{ "Density" => 120, "WarpSpeed" => 5 }
```

One trap for whoever checks this later: **`defaults domains` does not list the
domain.** ByHost domains are excluded from that listing, so its absence is not
evidence that no preferences exist. Glob the `ByHost` directory instead.

Nothing else is created. No caches under `~/Library/Caches`, no
`Application Support` directory, no LaunchServices registration worth undoing.

### Where the active-saver selection lives

```
$ plutil -p ~/Library/Preferences/ByHost/com.apple.screensaver.<UUID>.plist
{
  "moduleDict" => { "moduleName" => "Shell",
                    "path" => "/System/Library/ExtensionKit/Extensions/Shell.appex",
                    "type" => 0 },
  "idleTime" => 300, ...
}
```

So the selection is `moduleDict`, with both a name and a path. A legacy
`.saver` should appear here as its own name plus a path into
`~/Library/Screen Savers`, which is what detection will match on.

**Unverified:** the exact shape when a `.saver` rather than a system
`.appex` is selected. Confirming it means changing the machine's screen saver
setting, which was not done. Detection should therefore match **both**
`moduleName` and `moduleDict.path`, and treat a miss as "not selected" rather
than failing.

---

## 2. Constraints discovered

### An in-sheet "Uninstall" button is impossible

This was the most discoverable design, and it is ruled out on evidence rather
than taste:

```
$ codesign -d --entitlements - \
    /System/Library/Frameworks/ScreenSaver.framework/PlugIns/legacyScreenSaver.appex/Contents/MacOS/legacyScreenSaver
    com.apple.security.app-sandbox                                      true
    com.apple.security.temporary-exception.files.absolute-path.read-only  [...]
```

`legacyScreenSaver` is sandboxed and its filesystem exceptions are
**read-only**. Our code runs inside that sandbox, so it cannot delete its own
bundle or its preferences. Option closed.

### The host holds the executable open

```
$ lsof -p $(pgrep legacyScreenSaver) | grep Starfield
legacyScr 36926 ilirium txt REG ... /Users/ilirium/Library/Screen Savers/Starfield.saver/Contents/MacOS/Starfield
```

Unlinking succeeds regardless — this is Unix — but the inode survives until the
process restarts, and System Settings may keep showing a stale entry. The
uninstaller should offer to restart the host at the end.

---

## 3. Decisions taken

| Question | Answer |
|---|---|
| Form | **Shell script plus a double-clickable `.command`**, both shipped in the release zip |
| Settings | **Removed by default**; `--keep-settings` opts out |
| If Starfield is the selected saver | **Warn and proceed.** Never write to Apple's preference files |
| The `Render` settings bug (§6) | **Fix it in this change** |

The warn-only choice is the one worth defending. Rewriting
`com.apple.screensaver` would leave no dangling reference, but it means one
program editing another's preferences, in a file macOS caches and may rewrite,
with behavior unverifiable across macOS 13–15 from here. Telling the user to
pick another saver costs them one click and cannot break anything.

---

## 4. Design

### `uninstall.sh` (repository root, plain shell, like `build.sh`)

```
./uninstall.sh [--dry-run] [--keep-settings] [--all-users] [-y]
```

| Flag | Effect |
|---|---|
| `--dry-run` | print what would be removed, change nothing, exit 0 |
| `--keep-settings` | remove the bundle but leave `Density` / `WarpSpeed` |
| `--all-users` | also remove `/Library/Screen Savers/Starfield.saver`; needs `sudo` |
| `-y`, `--yes` | skip the confirmation prompt, for scripted use |

Behavior:

1. Collect targets: both install locations, and every `ByHost` plist matching
   `com.ilirium.Starfield.*.plist`.
2. If nothing is found, say so and exit 0. An uninstaller that reports failure
   when there is nothing to do is a nuisance in scripts.
3. Detect whether Starfield is the selected saver; warn if so.
4. Print the list, confirm unless `-y`, remove.
5. Offer to restart `legacyScreenSaver`.

**Safety properties.** This is the only script in the repository that deletes,
so it gets rules the others do not need:

- Every target is validated against an expected pattern immediately before
  removal — an empty or unset variable must never expand into `rm -rf /`.
- Only two shapes are ever removable: a path ending in `/Starfield.saver`
  under a known Screen Savers directory, and a file matching the ByHost
  preferences glob. Anything else is refused, loudly.
- `set -euo pipefail`, and no `rm -rf "$VAR"` without a preceding guard.

### `Resources/Uninstall Starfield.command`

Double-clickable wrapper: `cd` to its own directory, run `./uninstall.sh`,
pause before closing so the Terminal window does not vanish with the output.

A downloaded `.command` is quarantined exactly like the saver, so the first run
needs right-click → Open. This belongs in the README and in the generated
release notes, next to the equivalent note for the bundle.

### `Tools/uninstall-tests.sh`

The destructive path deserves a test more than anything else in the repo.

Build the full footprint under a throwaway `HOME`:

- `Screen Savers/Starfield.saver` — a real directory with a file inside
- **two** `ByHost` plists with different UUIDs, to exercise the glob
- decoys that must survive: another `.saver`, Apple's own
  `com.apple.screensaver.<UUID>.plist`, and an unrelated `com.ilirium.*` domain

Then assert:

| Case | Expectation |
|---|---|
| `-y` | our files gone, **every decoy intact** |
| `--dry-run` | nothing removed, exit 0 |
| `--keep-settings` | bundle gone, both plists intact |
| nothing installed | exit 0, no error |

The `--all-users` branch touches `/Library` and cannot be tested without root.
Give the script a documented **test-only override** for the system directory so
that branch is exercised against a temporary directory rather than shipped
untested.

---

## 5. Release mechanics

`Resources/Info.plist` goes to `1.1.0`. `release.yml` already fails the build
when the tag and `CFBundleShortVersionString` disagree, so no new check is
needed.

**The zip layout changes.** Today it is `ditto -c -k --keepParent
build/Starfield.saver`, producing an archive with a bare `Starfield.saver`.
With three items to ship, the packaging step stages a directory instead:

```
Starfield-1.1.0/
  Starfield.saver
  uninstall.sh
  Uninstall Starfield.command
```

`ditto` preserves the executable bit, so the scripts stay runnable. The
round-trip verification step and the README's first install instruction both
need updating for the new path.

---

## 6. The `Render` bug, fixed here

`Tools/Render/main.swift` writes `Density=120, WarpSpeed=5` into the **live**
user preference store on every run. That is why this machine reads 120 rather
than whatever was last chosen in System Settings: generating the artwork
silently overwrites the user's own settings.

It is in scope because it is the same store the uninstaller deletes, and
because the test harness needs an isolated store regardless.

The fix needs a seam, because `StarfieldView.commonInit()` hardcodes the
domain:

```swift
defaults = ScreenSaverDefaults(forModuleWithName: Config.bundleIdentifier)
```

So pointing only `Render` elsewhere would not work — the view would still read
the live domain. Add an overridable name to `Config`:

```swift
enum Config {
    static let bundleIdentifier = "com.ilirium.Starfield"
    /// The defaults domain the view reads. Overridden by the offscreen
    /// renderer so generating artwork does not overwrite the user's own
    /// settings. The saver itself never changes it.
    static var defaultsModuleName = bundleIdentifier
}
```

`Render` sets it to a scratch domain before constructing the view.
`StarfieldPreview` deliberately does **not** — `CLAUDE.md` documents that the
preview shares the real store, and that stays true.

The SVG drift check is unaffected: the SVGs come from `StarfieldEngine` with
fixed seeds, not from the view, so only the ephemeral PNGs are touched and no
artwork needs regenerating.

---

## 7. Files

| File | Change |
|---|---|
| `uninstall.sh` | **new** — the uninstaller |
| `Resources/Uninstall Starfield.command` | **new** — double-click wrapper |
| `Tools/uninstall-tests.sh` | **new** — destructive-path tests |
| `Sources/StarfieldView.swift` | `Config.defaultsModuleName`, read by the view |
| `Tools/Render/main.swift` | write to a scratch domain |
| `build.sh` | build/run the uninstaller tests beside `EngineTests` |
| `.github/workflows/ci.yml` | same, if not already covered via `build.sh` |
| `.github/workflows/release.yml` | staged zip layout; update the round-trip check and notes |
| `Resources/Info.plist` | `1.1.0` |
| `README.md` | an Uninstall section; adjust install paths for the new zip layout |
| `CLAUDE.md` | document `uninstall.sh` and its tests |
| `HANDOFF.md` | state |

---

## 8. Sequence

Four commits, tag last, stopping before the tag for review.

1. **`Render` and `Config`** — smallest, independent, verifiable alone.
2. **`uninstall.sh` and its tests** — the substance.
3. **`.command`, release packaging, README** — the shipping surface.
4. **Version bump and handoff**, then `git tag v1.1.0`.

---

## 9. Risks, and what will still be unverified

- **`--all-users` will get the least real-world exercise.** Nothing in this
  project ever installs to `/Library`; the README only ever uses `~/Library`.
  It is included because people do install savers system-wide by hand, and an
  uninstaller that silently misses half the possibilities is worse than none —
  but it is the branch most likely to harbour a mistake, which is why it gets a
  test seam rather than being left untested.
- **Selected-saver detection is best-effort**, for the reason in §1: the
  `moduleDict` shape for a legacy `.saver` was never observed. A miss degrades
  to "no warning", never to a failure or a wrong deletion.
- **The `.command` double-click path cannot be tested in CI.** It needs Finder
  and Terminal. CI can check the file exists, is executable, and passes
  `bash -n`; the actual double-click needs a human.
- **Nobody has run any of this on macOS 13, 14 or 15**, which is the standing
  caveat for the whole project.
