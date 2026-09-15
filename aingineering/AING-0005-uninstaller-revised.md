# Plan (revised): uninstaller, preview thumbnail, and a settings fix — v1.1.0

Status: **decided, not implemented.** Written 2026-09-15.

**Supersedes [AING-0003](AING-0003-uninstaller.md).** That plan was reviewed
twice, independently; [AING-0004](AING-0004-plan-review.md) records the sixteen
findings. Three were structural, and this document is what they turn the plan
into. AING-0003 is kept unamended as the record of what was first proposed —
the delta between the two is the most useful thing either of them contains.

This document is self-contained. Implementing from it needs no reading of the
other two.

Everything in §1 was measured on macOS 26.6.2, Apple Silicon, with the commands
shown, so it can be rechecked when macOS changes. Claims that were *not*
measured are labelled.

---

## 0. Scope

Three things ship together as v1.1.0, on the branch
**`uninstaller-and-a-few-fixes`** off `main`:

| | |
|---|---|
| **An uninstaller** | shell script, bundled *inside* the saver and shipped in the zip, with hermetic tests |
| **A System Settings thumbnail** | the bundle currently ships no preview image, so macOS shows a generic fallback |
| **A `Render` settings fix** | generating the artwork silently overwrites the user's own Density and WarpSpeed |

### What changed from AING-0003

| | Was | Now | Why |
|---|---|---|---|
| Removal order | `rm` first, offer host restart last | stop the host **first**, then `defaults delete`, then `rm`, then flush `cfprefsd` | a live client resurrects the plist after `rm`, with its old values — §2.1 |
| Test isolation | throwaway `HOME` | explicit directory overrides + a hermetic mode that skips all `defaults` calls | `cfprefsd` ignores `HOME`, so the old design deleted the developer's real settings — §2.2 |
| Thumbnail source | `Render`, driving an `NSView` | a new tool using `StarfieldEngine` + CoreGraphics | keeps AppKit off the critical path for producing the bundle — §5 |
| Uninstaller delivery | zip only | **inside the bundle**, plus the zip, plus raw commands in the README | zip-only is unreachable once Downloads is emptied — §3.4 |
| `Render` isolation | a new mutable `static var` on `Config` | the `ScreenSaverDefaultsStore` protocol the repo already has | the static is a hard error under `-swift-version 6`, and the seam already existed — §4 |

---

## 1. What an install leaves behind

| Path | Present on this machine |
|---|---|
| `~/Library/Screen Savers/Starfield.saver` | yes |
| `/Library/Screen Savers/Starfield.saver` | no — our README never creates it |
| `~/Library/Preferences/ByHost/com.ilirium.Starfield.<UUID>.plist` | yes — `{Density: 120, WarpSpeed: 5}` |

Nothing else: no `~/Library/Caches` entry, no `Application Support`, no
LaunchServices registration worth undoing.

**Trap for whoever rechecks this:** `defaults domains` does **not** list the
domain. ByHost domains are excluded from that listing, so its absence is not
evidence that no preferences exist. Glob the directory instead.

### The active-saver selection

```
$ plutil -p ~/Library/Preferences/ByHost/com.apple.screensaver.<UUID>.plist
{ "moduleDict" => { "moduleName" => "Shell",
                    "path" => "/System/Library/ExtensionKit/Extensions/Shell.appex",
                    "type" => 0 }, ... }
```

**Unverified:** the shape when a legacy `.saver` rather than a system `.appex`
is selected — confirming it means changing the machine's screen saver setting,
which was not done. Detection therefore matches on **both** `moduleName` and
`moduleDict.path`, and a miss means "not selected", never an error.

### Two constraints that close off options

**An in-sheet Uninstall button is impossible.** The host is sandboxed with
read-only file exceptions, and our code runs inside that sandbox:

```
$ codesign -d --entitlements - .../legacyScreenSaver.appex/Contents/MacOS/legacyScreenSaver
    com.apple.security.app-sandbox                                        true
    com.apple.security.temporary-exception.files.absolute-path.read-only  [...]
```

**The host holds the executable mapped.**

```
$ lsof -p $(pgrep legacyScreenSaver) | grep Starfield
legacyScr ... txt REG ... /Users/ilirium/Library/Screen Savers/Starfield.saver/Contents/MacOS/Starfield
```

---

## 2. The two findings that reshaped the design

### 2.1 Deleting the plist does not remove the setting

A live client holding the domain open keeps the values in `cfprefsd`, and its
next write **recreates the file with the old values in it**:

```
$ defaults -currentHost write <probe> Density -int 77
$ # a helper opens the domain via CFPreferencesCopyValue
$ rm ~/Library/Preferences/ByHost/<probe>.*.plist      -> file gone
  read back: 77                                         <- client still sees it
  file now:  { "Density" => 77, "Touched" => 1 }        <- and it is back
```

`legacyScreenSaver` is exactly such a client. A domain with *no* live client
does stay deleted after a plain `rm` — so this is about live clients
specifically, which is why ordering is the fix rather than a different delete.

The mirror trap: `defaults -currentHost delete <domain>` reports the domain
gone but **leaves the plist on disk**. Neither operation alone suffices.

### 2.2 `cfprefsd` ignores `HOME`, so tests cannot be isolated that way

```
$ HOME=/tmp/fakehome defaults -currentHost read com.ilirium.Starfield Density
120                                       <- the real value

$ HOME=/tmp/fakehome defaults -currentHost write <probe> K -int 1
  in fake home:  total 0
  in real home:  <probe>.A8C59E65-….plist  <- wrote to the REAL home
```

Fixing 2.1 requires `defaults`. So a test suite that isolates with `HOME` and
runs a script calling `defaults` is **deleting the developer's real
preferences while claiming to be hermetic**. The seam in §3.3 exists because of
this.

---

## 3. The uninstaller

### 3.1 Interface

```
./uninstall.sh [--dry-run] [--keep-settings] [--all-users] [-y] [-h]
```

| Flag | Effect |
|---|---|
| `--dry-run` | print what would be removed, change nothing, exit 0 |
| `--keep-settings` | remove the bundle, keep `Density` / `WarpSpeed` |
| `--all-users` | also remove `/Library/Screen Savers/Starfield.saver` |
| `-y` | skip confirmation |

### 3.2 Order of operations

Order is load-bearing, per §2.1. Steps 3–7 only run outside hermetic mode.

1. **Collect** targets: both install locations, every ByHost plist matching the
   domain, and `~/Library/Preferences/com.ilirium.Starfield*.plist` (non-ByHost,
   see §4).
2. **Check** every target is removable *before* removing anything — writability
   and, for `/Library`, whether elevation is available. A partial uninstall that
   fails halfway is worse than one that refuses up front.
3. **Warn** if Starfield is the selected saver. Never write to Apple's plists.
4. **Confirm**, unless `-y`. `--dry-run` stops here.
5. **Stop the clients**: `killall legacyScreenSaver || true`, and tell the user
   to quit System Settings, which caches the module list independently.
6. **Remove the bundle(s).**
7. **Remove the settings** unless `--keep-settings`:
   `defaults -currentHost delete com.ilirium.Starfield || true`, then `rm -f`
   every matching plist (including foreign UUIDs, which are cold), then
   `killall -u "$USER" cfprefsd || true`.

### 3.3 Safety, and the test seam

This is the only script in the repository that deletes, so it gets rules the
others do not.

**Three overridable directories**, defaulting to the real locations:

```sh
: "${STARFIELD_USER_SAVER_DIR:=$HOME/Library/Screen Savers}"
: "${STARFIELD_SYSTEM_SAVER_DIR:=/Library/Screen Savers}"
: "${STARFIELD_BYHOST_DIR:=$HOME/Library/Preferences/ByHost}"
```

If **any** is overridden, the script is in **hermetic mode**: it touches files
only, and skips every `defaults`, `cfprefsd` and `killall` call. That is what
makes the destructive path testable without `cfprefsd` reaching around the
test into the real user's preferences (§2.2).

**Guards:**

- `shopt -s nullglob`. Without it an unmatched glob expands to *its own
  literal*, which then **matches** the validation pattern and hands `rm` a path
  containing `*`:
  ```
  $ bash -c 'set -euo pipefail; for f in /tmp/no_match_*.plist; do echo "GOT [$f]"; done'
  GOT [/tmp/no_match_*.plist]
  ```
- Validate the UUID with a real pattern, `[0-9A-Fa-f-]{36}`, not `*` — so a
  future sub-domain can only be removed deliberately.
- Only two shapes are ever removable: a path ending `/Starfield.saver` under a
  known saver directory, and a plist matching the validated domain pattern.
  Anything else is refused loudly.
- `set -euo pipefail`, with `|| true` on `killall` and on `PlistBuddy` reads.
  Both return non-zero on "nothing there", which would otherwise abort a
  **successful** uninstall:
  ```
  $ killall no_such_proc_xyz; echo $?
  No matching processes belonging to you were found
  1
  ```
- Test symlinked installs with `-h` and remove the link deliberately rather than
  by luck — a developer may have `ln -s build/Starfield.saver ~/Library/…`.

**Never run the whole script as root.** `sudo ./uninstall.sh --all-users` is the
obvious invocation and it is wrong: `defaults` as root targets *root's* domain,
not the user's, and user-path files it touches end up root-owned. Refuse if
`$EUID` is 0; elevate only the single `rm -rf` of the system path. If
`$SUDO_USER` is set, exit with a message rather than guessing.

### 3.4 Delivery — three routes, because the zip is not enough

The argument for having an uninstaller at all is that a hand-written `rm` is
easy to get incomplete. That argument applies most to the person who installed
six months ago and has since emptied Downloads — who, under a zip-only design,
has neither the script nor a documented procedure.

| Route | Mechanism |
|---|---|
| **Inside the bundle** | `build.sh` copies `uninstall.sh` and the `.command` into `Contents/Resources/` before signing, so they travel with the installation and are sealed by the signature |
| **In the release zip** | beside the saver, for people who still have the download |
| **In the README** | a literal copy-pasteable `rm` block, for people who have neither |

**Self-deletion wrinkle.** When run from inside the bundle, the script is
deleting the file it is executing. `bash` may re-read a script mid-run, so the
bundled copy must detect this — compare its own path against the target — and
re-exec from a copy in `$TMPDIR` before removing anything.

### 3.5 Tests — `Tools/uninstall-tests.sh`

Build the footprint under overridden directories (§3.3), not a fake `HOME`:

- `Starfield.saver` as a real directory with a file inside
- **two** ByHost plists with different UUIDs, to exercise the glob
- decoys that must survive: another `.saver`, Apple's own
  `com.apple.screensaver.<UUID>.plist`, an unrelated `com.ilirium.*` domain

| Case | Expectation |
|---|---|
| `-y` | our files gone, **every decoy intact** |
| `--dry-run` | nothing removed, exit 0 |
| `--keep-settings` | bundle gone, both plists intact |
| nothing installed | exit 0, no error |
| unmatched glob | no path containing `*` ever reaches `rm` |
| symlinked install | link removed, target untouched |
| run as root | refuses |

**Two things the hermetic suite cannot cover, and how they are covered anyway:**

- The `--all-users` seam means `/Library/Screen Savers` is the one string never
  executed — and a typo there is exactly the bug the seam hides. So: **assert
  the default literal against the script source**, textually.
- The `cfprefsd` half (§2.1) is skipped in hermetic mode. It gets one separate,
  **opt-in, explicitly non-hermetic** test against a throwaway domain, not run
  by default and not run in CI.

---

## 4. The `Render` settings fix

`Tools/Render/main.swift` writes `Density=120, WarpSpeed=5` into the **live**
user preference store on every run — which is why this machine reads 120 rather
than whatever was last chosen.

Pointing only `Render` elsewhere does not work: `StarfieldView.commonInit()`
hardcodes the domain, so the view keeps reading the live one.

**Use the seam the repo already has.** `Sources/ConfigController.swift` defines
`protocol ScreenSaverDefaultsStore`, with `extension UserDefaults:
ScreenSaverDefaultsStore {}`, written so the config sheet could be driven with a
substitute store. Give `StarfieldView` the same treatment: hold a
`ScreenSaverDefaultsStore?`, and add a method to swap it and re-read. `Render`
constructs the view, injects a scratch `UserDefaults`, reloads. The saver never
calls it.

Extend the protocol with whatever `commonInit` needs (`register(defaults:)`)
rather than widening the type.

**Explicitly rejected:** a `static var` on `Config`. It compiles today only
because `build.sh` passes no `-swift-version`:

| mode | result |
|---|---|
| default — today | clean |
| `-strict-concurrency=complete` | warning: *"…an error in the Swift 6 language mode"* |
| `-swift-version 6` | **error: not concurrency-safe … [#MutableGlobalVariable]** |

**Three details that decide whether this fix actually fixes anything:**

1. **Drop the `?? .standard` fallback** on that line. If the scratch store ever
   returns nil, the fallback silently reverts to clobbering — the exact bug.
2. **`removePersistentDomain(forName:)` when `Render` finishes**, so the scratch
   domain does not become the next thing an uninstaller has to know about.
3. **Know where the scratch domain lands.** Measured:
   `UserDefaults(suiteName:)` writes to
   `~/Library/Preferences/com.ilirium.Starfield.render.plist` — **plain
   Preferences, not ByHost** — which a ByHost-only glob would miss. Hence the
   extra sweep in §3.2 step 1. (`ScreenSaverDefaults` on a scratch name would
   instead land in ByHost and match the glob only if the name keeps the
   `com.ilirium.Starfield.` prefix. Either is fine; the point is to choose
   deliberately and assert the choice in a test.)

---

## 5. The System Settings thumbnail

### What macOS looks for — measured

```
$ find "/System/Library/Screen Savers/Random.saver" -type f
  Contents/Resources/thumbnail.png       90 x 58
  Contents/Resources/thumbnail@2x.png   180 x 116
```

It is a **filename convention** — `Random.saver`'s `Info.plist` declares no
thumbnail, preview, poster or icon key. `FloatingMessage.saver` ships none at
all, so it is optional. Our `Contents/Resources` is empty, which is why a
generic fallback appears.

**Unverified, and it gates this whole section:** whether System Settings on
macOS 14+ still honours the convention for *third-party* legacy savers.
`Random.saver` is Apple's own and the convention predates System Settings.
**This is step 0** — see §7.

### Generated from the engine, not from the view

AING-0003 proposed extending `Render`. That put AppKit, `NSView` and
`cacheDisplay` on the critical path for *producing the bundle*, which partly
undoes the reason `ci.yml` is split into two jobs — the engine job exists
precisely so arithmetic stays verifiable without a window server.

So: a new **`Tools/Thumbnail/`**, linking `StarfieldEngine.swift` plus
CoreGraphics and ImageIO for the PNG encode. No `NSView`, no AppKit, no window
server. The rule AING-0003 stated — *generated from `StarfieldEngine` with a
fixed seed, never hand-drawn* — is satisfied either way, and this keeps the
framework-free property the repo values.

It also sidesteps a trap in extending `Render`: that file is top-level code
which writes `single.png` and `trails.png` into its output directory **before
any flag is consulted**, so a `--thumbnail Contents/Resources` would deposit
both into the shipped, signed bundle. (`Render` should still be restructured
into explicit modes, and its `args[$0 + 1]` flag idiom fixed — it traps on
out-of-bounds when the flag is last.)

### What the image should be

- **Render at the target aspect directly.** 90×58 is a ratio of 1.5517, neither
  16:9 nor 4:3. Rendering at the view's ratio and scaling down stretches the
  stars into rectangles — conspicuous in a project whose premise is that the
  stars are *square* because the original used `PatBlt`.
- **A single instant will not read at 90 pixels.** The saver at rest is 1px
  white dots on black; scaled to a 90×58 box that is close to an empty
  thumbnail. Use a short trail composite — the technique behind
  `docs/assets/trails.svg` — so the radial motion is legible. Density and star
  size want tuning for the small canvas rather than inheriting display defaults.
- **Legibility is a judgement call no test settles.** It needs looking at, in
  the pane, at actual size.

### Where the files live

"Source only, no binaries committed" is a standing decision, and the README art
is SVG *specifically* so it stays text. So the thumbnails are **generated at
build time and committed nowhere**. No CI drift check is needed, unlike the
SVGs: they are regenerated every build and cannot fall out of step.

### The build reorder, and why it is mandatory

The signature covers `Contents/Resources`. **Confirmed:** adding files there
after signing breaks the bundle —

```
$ codesign --verify --deep --strict build/Starfield.saver
build/Starfield.saver: a sealed resource is missing or invalid
```

— and re-signing seals them (`Sealed Resources … files=2`). So:

```
now:    compile saver -> Info.plist -> codesign -> compile tools -> test
needed: compile Thumbnail -> generate thumbnails
        -> assemble saver (binary + Info.plist + thumbnails + uninstaller)
        -> codesign -> EngineTests -> LoadTest
```

`Tools/Thumbnail` links only `StarfieldEngine.swift`, so building it first costs
nothing and drags in no frameworks.

---

## 6. Packaging and release

**Stage an unversioned folder.** AING-0003 proposed `Starfield-1.1.0/`, which
bakes a version into the path users are told to `cd` into and goes stale every
release. Stage as `Starfield/` and keep the version in the zip filename only.

```
Starfield-1.1.0.zip
  Starfield/
    Starfield.saver
    uninstall.sh
    Uninstall Starfield.command
```

- `uninstall.sh` must be **committed mode `100755`**. Git tracks the bit —
  `build.sh` and `Tools/pe-imports.py` are `755` today — and `ditto -c -k`
  preserves it through both `ditto -x` and `unzip`. Miss it and the `.command`
  wrapper's `./uninstall.sh` fails for everyone.
- The `.command` source lives in **`packaging/`**, not `Resources/`.
  `Resources/` in this repo means bundle content — it holds exactly one file,
  `Info.plist`, which `build.sh` copies into `Contents/`.
- **`release.yml`'s notes heredoc names the old layout in two places** and must
  change with it. AING-0003 listed "update the round-trip check" and missed the
  notes body — the text users actually follow.
- `Resources/Info.plist` goes to `1.1.0`; `release.yml` already fails the build
  if the tag disagrees.

**Unverified, and it should be marked so rather than asserted:** that a
downloaded `.command` needs only right-click → Open. A quarantined *shell
script* is not the same case as a signed bundle, and recent macOS has been
removing that bypass in favour of Privacy & Security → Open Anyway. This is the
only entry point non-terminal users have.

---

## 7. Sequence

**Step 0, before anything is written** — confirm §5's convention still holds for
third-party savers. Build a bundle with placeholder thumbnails, install, look at
the Screen Saver pane. No commit. If it fails, §5 is replanned and the other two
features proceed without it.

Then **five commits**, stopping before the tag:

1. **`Render` and the defaults seam** (§4) — smallest, independent, verifiable
   alone.
2. **`uninstall.sh` and its tests** (§3) — the substance.
3. **`Tools/Thumbnail` and the `build.sh` reorder** (§5) — kept separate because
   it touches signing order, where a mistake is silent.
4. **Packaging** (§6) — `.command`, zip staging, README, release notes.
5. **Version bump, `CLAUDE.md`, `HANDOFF.md`.**

Then land on `main` with `--no-ff`, then `git tag v1.1.0`: merge first, tag
second.

`CLAUDE.md` needs more than a mention — it currently says `build.sh` "builds
three tools and runs two of them" and documents `Render`'s usage line. This plan
falsifies both.

---

## 8. What stays unverified

- **The thumbnail convention for third-party savers** (§5). Everything in that
  section rests on it; it is step 0 for exactly that reason.
- **Thumbnail legibility at 90 pixels** — a judgement call, not a test.
- **The `moduleDict` shape when a `.saver` is selected** (§1). Detection
  degrades to "no warning", never to a wrong deletion.
- **The `.command` quarantine path** (§6), which cannot be exercised in CI —
  it needs Finder, Terminal, and a genuinely downloaded file.
- **`--all-users`**, which nothing in this project creates. AING-0003 called it
  exotic; that is now doubted — the README's *first* recommended install is a
  double-click handed to System Settings, historically a route by which copies
  land in `/Library/Screen Savers`. Speculative on macOS 14+, but it argues for
  keeping the flag rather than dropping it.
- **Anything on macOS 13, 14 or 15**, the standing caveat for the whole project.
