# A GUI uninstaller in AppleScript — v1.2.0

Status: **feasibility settled, two decisions open, not implemented.**
Written 2026-09-15.

The question that started it: can a small GUI app drive `uninstall.sh` and offer
its modes as buttons? Yes. §1 is measured and is not in question. §3 and §4 are
**proposals, not decisions** — they are the two things to settle before anyone
writes code.

> **Open decisions**
>
> 1. **§3 — `--all-users`.** Proposed: drop it from the GUI. There is a third
>    option, added after the first draft, that may change the answer.
> 2. **§4 — the `.command`.** Proposed: ship the app *alongside* it. Replacing
>    it, or not building the app at all, are both live.
>
> An independent review of this document is wanted **at implementation time**,
> not now.

Everything in §1 was measured on macOS 26.6.2, Apple Silicon, with the commands
shown. Claims that were not measured are labelled.

---

## 0. Scope

One new shipping artifact: `Uninstall Starfield.app`, built from AppleScript
source, ad-hoc signed like the saver, shipped in the release zip.

It is a **front end only**. All removal logic stays in `uninstall.sh`, which is
tested, guarded, and already ships inside the bundle. The app finds that script
and runs it. It must never grow its own idea of what to delete.

---

## 1. What was measured

| Claim | Command | Result |
|---|---|---|
| Builds with Command Line Tools alone | `which osacompile` | `/usr/bin/osacompile`; `xcode-select -p` is the CLT path. No Xcode. |
| Produces a real app bundle | `osacompile -o "X.app" x.applescript` | 572K: `Contents/MacOS/applet`, `Contents/Resources/Scripts/main.scpt` |
| Signs like everything else here | `codesign --force --deep --sign -` then `--verify --deep --strict` | valid |
| Can drive the uninstaller | `do shell script` against a hermetic tree | output returned as a string, suitable for a dialog |
| **Maximum 3 buttons** in `display dialog` | four buttons | error `-50`, *"Maximum of 3 buttons allowed."* |
| `choose from list` takes more | five items | compiles |
| **Handlers are callable headlessly** | `load script` + `tell L to flagsFor(…)` | returns the flag string, no UI shown |

Two behaviours matter more than the rest.

### 1.1 There is no stdin, so `-y` is mandatory

`do shell script` gives the child no TTY. `uninstall.sh` prompts `Continue?
[y/N]` and calls `read`, which hits EOF; `set -e` then aborts.

Measured: the run returns error 1, and **nothing is removed**. That is a safe
failure, not a dangerous one — but it means the app must do its own
confirmation in a dialog and then pass `-y`.

### 1.2 Handlers can be tested without showing a window

```
$ osacompile -o lib.scpt lib.applescript
$ osascript -e 'set L to load script POSIX file "…/lib.scpt"' \
            -e 'tell L to flagsFor("Keep my settings")'
-y --keep-settings
```

This is the finding the whole design rests on. AppleScript UI is untestable, but
AppleScript *logic* is not, provided the logic lives in handlers that take
arguments and return values rather than reading dialogs directly.

---

## 2. The design: a thin skin over pure handlers

Two files, deliberately separated by testability.

**`packaging/UninstallStarfieldLib.applescript`** — pure handlers, no UI, no
side effects:

| Handler | Returns |
|---|---|
| `flagsFor(mode)` | the `uninstall.sh` flags for a menu label; `error` on anything unknown |
| `needsConfirmation(mode)` | whether this mode destroys something |
| `summaryFor(mode)` | the sentence shown in the confirmation dialog |
| `uninstallerPath(homePath)` | where the installed script should be |

**`packaging/UninstallStarfield.applescript`** — the app. Finds the script,
shows `choose from list`, confirms if needed, runs `do shell script`, shows the
output. It contains no decisions that are not delegated to the library.

`osacompile` takes multiple sources, so the two compile into one `.app` with no
runtime lookup and nothing extra to install.

### The modes

Four, not five — see §3.

| Menu label | Flags |
|---|---|
| Remove Starfield and its settings | `-y` |
| Remove Starfield, keep my settings | `-y --keep-settings` |
| Refresh the Screen Saver preview | `--refresh-preview` |
| Show me what would be removed | `--dry-run` |

Ordering is deliberate: the common case first, the harmless inspection last.
`--dry-run` and `--refresh-preview` skip the confirmation dialog, because
neither removes the saver.

---

## 3. `--all-users` — OPEN

**The constraint is real; the conclusion is not yet made.**

AppleScript's only elevation is `do shell script … with administrator
privileges`, which runs the **entire** command as root. `uninstall.sh` refuses
that on purpose: as root, `defaults` targets root's domain rather than the
user's, and any user-path file it touches ends up root-owned. The script
elevates only its single `rm` of the system path, and `sudo` has no TTY to
prompt on from a GUI.

So passing `--all-users` straight through does not work. Three ways forward:

| | |
|---|---|
| **A. Omit the mode** | The GUI simply does not offer it. Nothing this project does creates `/Library/Screen Savers/Starfield.saver`; anyone in that position can run the script directly. Simplest, and the app stays a pure front end. |
| **B. Elevate only the one `rm`, in the app** | The app runs `uninstall.sh` unelevated, then issues a *separate* `do shell script "rm -rf /Library/Screen Savers/Starfield.saver" with administrator privileges`. This mirrors exactly what the script does internally, and gets a native authentication dialog rather than a dead `sudo` prompt. |
| **C. Detect and defer** | Offer the mode, and if the system copy exists, tell the user the one command to run in Terminal. Honest, but it is a GUI that hands you a terminal command. |

**B is the interesting one and was missed in the first draft.** It preserves
the guard's *intent* — elevate one `rm`, never the whole script — while giving
the GUI full parity with the CLI. Its cost is that the app then contains a
hardcoded removal path of its own, which is precisely the thing §0 says it must
never grow. That tension is the decision.

If B is chosen, the path literal must be asserted against `uninstall.sh`'s own
default, textually, the way the test suite already does for the script's
directory literals — otherwise the two can drift and the app deletes something
the script does not.

**Still rejected:** re-exec'ing the *whole* script under `with administrator
privileges`. It defeats the guard rather than honouring it, and would leave
root-owned files in the user's Library.

---

## 4. The `.command`, and Gatekeeper — OPEN

Worth stating plainly rather than assuming away, because it is the strongest
argument *against* building it at all.

This project has no Developer ID, so the app would be ad-hoc signed. A
downloaded, ad-hoc-signed `.app` is quarantined and refused with the
unidentified-developer dialog. The friendlier interface therefore arrives
wrapped in a scarier first-run experience than the shell script it replaces.

**Unverified:** exactly how macOS 26 treats a quarantined ad-hoc-signed applet
versus a quarantined `.command`. Both are blocked; which is *more* annoying was
not measured, and recent macOS has been moving both toward Privacy & Security →
Open Anyway rather than right-click → Open.

**Proposed, not decided: `Uninstall Starfield.command` stays.** Three options:

| | |
|---|---|
| **A. Ship both** | App first in the README, `.command` documented as what to use if macOS refuses the app. Mild clutter — three uninstall routes in one zip — but the friendly route always has a fallback. |
| **B. App replaces the `.command`** | Cleaner zip, one obvious GUI route. Risk: if Gatekeeper refuses the app, the only remaining routes are a terminal command and the README. |
| **C. Do not build the app** | Keep the `.command`, which already works, is 23 lines, needs no build step, and shows exactly what happened. Costs nothing and adds nothing. |

The honest framing for C: this feature trades four new moving parts — a source
pair, a build step, a signing step, a test suite — for a window of buttons
instead of a window of text. That is a real improvement for people who will not
open Terminal, and a real cost. Whether it is worth it is a judgement about the
audience, not about the technology, and §1 has nothing to say about it.

---

## 5. Tests — `Tools/applescript-tests.sh`

Run by `build.sh`, alongside the uninstaller suite.

**The library, headlessly** (§1.2). No window is ever shown:

| Case | Expectation |
|---|---|
| each of the four labels | the exact flag string |
| an unknown label | errors rather than returning a default |
| every returned flag string | accepted by `uninstall.sh --help`-style parsing, not a typo |
| `needsConfirmation` | true for the two destructive modes, false for the other two |
| `uninstallerPath("/Users/x")` | the `Contents/Resources/uninstall.sh` path |

The third case is the one that earns its keep. A flag string is a *string*, and
`--dryrun` would compile, pass every other test, and fail only when a user
clicked it. The test feeds each flag to the real script with the hermetic
overrides set and asserts a zero exit, so a typo cannot survive.

**The app bundle:**

- `osacompile` succeeds — the compile is the syntax gate.
- the built `.app` has `Contents/MacOS/applet` and `Contents/Resources/Scripts/main.scpt`
- `codesign --verify --deep --strict` passes after signing

**What cannot be tested, and is not pretended otherwise:** that the dialogs
appear, read well, and are laid out sensibly. That needs a human double-clicking
the app. It goes on the distrust list, like thumbnail legibility.

---

## 6. Build and packaging

`build.sh` gains a step next to the thumbnail generation:

```sh
osacompile -o "build/Uninstall Starfield.app" \
    packaging/UninstallStarfieldLib.applescript \
    packaging/UninstallStarfield.applescript
codesign --force --deep --sign - "build/Uninstall Starfield.app"
```

It is **not** copied into the saver bundle. The bundle carries `uninstall.sh`,
which is what the app drives; putting a GUI app inside a screen saver plugin
would be odd, and it would be sealed by the saver's signature for no benefit.

The release zip becomes:

```
Starfield-1.2.0.zip
  Starfield/
    Starfield.saver
    Uninstall Starfield.app          <- new, primary
    Uninstall Starfield.command      <- fallback if Gatekeeper blocks the app
    uninstall.sh
```

`release.yml`'s round-trip check gains the app: signature valid after unpacking,
and `Contents/MacOS/applet` present.

**Unverified:** whether `ditto -c -k` round-trips an applet bundle's resource
fork cleanly. It does for the `.saver`, and an applet is an ordinary bundle, but
`applet.rsrc` is the one file in it that is not a plain resource. Check it in
the round-trip step rather than assuming.

---

## 7. Sequence

Three commits, on a branch off `main` after 1.1.0 lands.

1. **The library and its tests** (§2, §5) — pure handlers, testable, no UI. The
   substance.
2. **The app and the build step** (§2, §6) — the thin skin, `osacompile`,
   signing.
3. **Packaging and docs** — zip staging, `release.yml` round-trip, README,
   `CHANGELOG.md`, version bump to 1.2.0.

`CLAUDE.md` needs a line: `build.sh` will then build five things and run four
suites.

---

## 8. What stays unverified

- **Whether the dialogs read well.** No test settles it; someone has to
  double-click the app.
- **Quarantine behaviour for an ad-hoc-signed applet** (§4), and whether it is
  better or worse than the `.command`.
- **`ditto` round-tripping `applet.rsrc`** (§6).
- **§3 and §4 themselves**, which are open decisions rather than unverified
  claims. They are listed here too so a reader skimming only this section does
  not mistake the document for settled.
- **Whether the app is wanted at all.** `Uninstall Starfield.command` already
  works, is 23 lines, needs no build step, and shows the user exactly what
  happened in Terminal. This adds an artifact to build, sign, package and test
  in order to replace a window of text with a window of buttons. That is a real
  improvement for non-terminal users and a real cost in moving parts, and the
  trade is worth revisiting if the build starts feeling heavy.
