# Review of AING-0003 (the v1.1.0 plan)

Status: **review complete, plan not yet amended.** Written 2026-09-15, against
`aingineering/AING-0003-uninstaller.md` as of commit `52855f9`.

Two independent reviews, deliberately not shared with each other:

- **A** — the plan's own author, re-reading it.
- **B** — a fresh agent with no memory of writing it, given the repository and
  the document and asked for problems.

They overlapped on six findings and diverged on eleven, which is the useful
part: the overlaps are the ones most likely to be real, and the divergences are
what a single pass would have shipped.

Findings are merged below, deduplicated, severity-ordered. Each says whether it
was **confirmed by running something** or **inferred**, because the plan's own
convention is that reasoned-but-unchecked claims get labelled as such.

**Nothing here invalidates the plan's shape.** The uninstaller, the thumbnail
and the `Render` fix all remain the right things to build. What follows changes
how, and in three places changes the order.

---

## HIGH

### 1. Deleting the plist does not remove the setting, and the plan's step order guarantees it

**Confirmed by B, experimentally.** A live client holding the domain open keeps
the values in `cfprefsd`, and its next write **recreates the file with the old
values in it**:

```
$ defaults -currentHost write <probe> Density -int 77
$ # a helper opens the domain via CFPreferencesCopyValue
$ rm ~/Library/Preferences/ByHost/<probe>.*.plist       -> file gone
  read back: 77                                          <- client still sees it
  file now:  { "Density" => 77, "Touched" => 1 }         <- and it is back
```

`legacyScreenSaver` is exactly such a client — AING-0003 §2 already documents
that it is running and holding our bundle open. So the default path and
`--keep-settings` can produce **identical observable results**.

The mirror trap, also observed: `defaults -currentHost delete <domain>` reports
the domain gone but **leaves the plist on disk**. Neither operation alone is
sufficient.

A's complementary probe: a domain with *no* live client stays deleted after a
plain `rm`. So this is specifically about live clients, not a general caching
problem — which is what makes the ordering the fix.

**Fix.** AING-0003 §4 step 5 ("offer to restart `legacyScreenSaver`") moves to
the front, and removal becomes: restart/kill the host → `defaults -currentHost
delete` for the current-host UUID → `rm` every ByHost plist including foreign
UUIDs (those are cold, so `rm` suffices) → `killall -u "$USER" cfprefsd || true`.
Also advise quitting System Settings, which caches the module list separately.

### 2. The test harness would operate on the developer's real preferences

**Confirmed independently by both.** `defaults` talks to `cfprefsd` over XPC and
ignores `HOME` entirely:

```
$ HOME=/tmp/fakehome defaults -currentHost read com.ilirium.Starfield Density
120                                    <- the real value, not the fake home's

$ HOME=/tmp/fakehome defaults -currentHost write <probe> K -int 1
  in fake home:  total 0
  in real home:  <probe>.A8C59E65-….plist      <- wrote to the REAL home
```

This puts §4 in a bind it never notices: fixing finding 1 *requires* `defaults`,
and the moment `uninstall.sh` calls `defaults`, `Tools/uninstall-tests.sh`
running under a throwaway `HOME` is **deleting the real user's settings while
pretending to be hermetic**. A destructive test that destroys the thing it is
simulating.

**Fix.** Make the ByHost *directory* an overridable variable, exactly like the
`--all-users` seam the plan already proposes, and gate every `defaults` /
`cfprefsd` call on "no override in effect". Hermetic tests then exercise the
file half only; the cfprefsd half needs one separate, opt-in, explicitly
non-hermetic test against a scratch domain.

### 3. `--all-users` never says who runs it, and the obvious reading is wrong

**B, partly inferred.** The plan says `--all-users` "needs `sudo`" and stops
there. The natural reading — `sudo ./uninstall.sh --all-users` — breaks the
per-user half in ways that hold regardless of sudoers configuration: `defaults`
run as root targets **root's** preference domain, not the user's, and any
user-path file it touches ends up root-owned.

A's related finding: the plan deletes user files *before* system files, so
without privileges the system delete fails **after** the user's files are
already gone — a half-uninstalled machine, reported at the end.

**Fix.** Refuse to run the whole script as root. `sudo` only the single
`rm -rf` of `/Library/Screen Savers/Starfield.saver`. If `$SUDO_USER` is set,
either resolve user paths from it deliberately or exit with a message. And
check writability of every target **before** removing anything.

---

## MEDIUM

### 4. `static var` is a hard error in Swift 6 language mode

**Confirmed independently by both**, compiling §6's exact snippet with
`build.sh`'s flags on the toolchain here (Apple Swift 6.4):

| mode | result |
|---|---|
| default — what `build.sh` uses today | clean |
| `-strict-concurrency=complete` | warning: *"…this is an error in the Swift 6 language mode"* |
| `-swift-version 6` | **error: static property is not concurrency-safe … [#MutableGlobalVariable]** |

It compiles today only because `build.sh` passes no `-swift-version` and 6.4
still defaults to Swift 5 mode. A landmine for anyone who bumps it.

**Fix — and B found the better one, which A missed.** The repo *already has the
right seam*: `Sources/ConfigController.swift` defines
`protocol ScreenSaverDefaultsStore` with `extension UserDefaults:
ScreenSaverDefaultsStore {}`, written precisely so the config sheet could be
driven with a substitute store. Give `StarfieldView` an injectable store
instead of inventing a mutable global. `nonisolated(unsafe) static var` is the
fallback if injection proves awkward against the fixed
`init(frame:isPreview:)` signature.

### 5. The `Render` fix manufactures the exact state the uninstaller exists to remove

**Both, from different angles, and the difference matters.**

A measured that `UserDefaults(suiteName:)` writes to
`~/Library/Preferences/com.ilirium.Starfield.render.plist` — **plain
Preferences, not ByHost** — which the plan's ByHost-only glob would miss
entirely.

B measured that `ScreenSaverDefaults(forModuleWithName:)` on a scratch name
still creates a real persistent **ByHost** plist, on every build and every CI
run — and that whether the uninstaller catches it is decided by a naming choice
the plan never makes: `com.ilirium.Starfield.Render` matches
`com.ilirium.Starfield.*.plist`; `com.ilirium.StarfieldRender` does not.

So the cleanup depends on **which API** and **which name**, and AING-0003
specifies neither.

B also spotted that `Tools/Render/main.swift` currently ends that line with
`?? .standard`. If the scratch domain ever returns nil, the "fix" silently
falls back to clobbering — the precise bug it was written to remove.

**Fix.** Decide the API and the name explicitly; drop the `?? .standard`
fallback; have `Render` call `removePersistentDomain(forName:)` when it
finishes so nothing persists at all; and if a scratch domain is kept, assert
its name against the uninstaller's glob in a test.

### 6. The uninstaller is unreachable by the people who need it

**Both.** It ships only inside the release zip. §0's own argument is that a
hand-written `rm` is likely to be incomplete — yet someone who installed six
months ago and emptied Downloads has neither the script nor a documented manual
procedure.

**Fix — B's is better than A's.** A proposed putting raw `rm` commands in the
README. B proposed copying `Uninstall Starfield.command` into
`Starfield.saver/Contents/Resources/` at build time, beside the thumbnails and
before `codesign`: it then travels with the installation, is sealed by the
signature, and the §7 build reorder is already doing exactly that work. Do
both — bundle it, and keep a copy-pasteable fallback in the README.

### 7. `killall` exits 1 when nothing matches, and `set -e` aborts on it

**B, confirmed.**

```
$ killall no_such_proc_xyz; echo $?
No matching processes belonging to you were found
1
```

Step 5 runs last, so a *successful* uninstall on a machine where the saver was
never active would exit non-zero. Same class: `PlistBuddy -c 'Print
:moduleDict:path'` returns non-zero when the key is absent, which under
`set -e` turns §1's "treat a miss as not selected" into an abort.

**Fix.** `|| true` on both, and design the selected-saver probe to tolerate a
missing key by construction.

### 8. An unmatched glob expands to its own literal and walks through the safety guard

**B, confirmed.**

```
$ bash -c 'set -euo pipefail; for f in /tmp/no_match_*.plist; do echo "GOT [$f]"; done'
GOT [/tmp/no_match_*.plist]
```

The literal `com.ilirium.Starfield.*.plist` **matches** §4's stated validation
rule ("a file matching the ByHost preferences glob"), so the guard approves it
and `rm` receives a path containing `*`. Harmless with `rm -f`, but it defeats
the guard in principle and makes "nothing found → exit 0" unreliable.

**Fix.** `shopt -s nullglob`, and validate the UUID with a real pattern
(`[0-9A-Fa-f-]{36}`) rather than `*` — so a future sub-domain (finding 5) can
only be deleted deliberately.

### 9. The build reorder puts AppKit on the critical path for producing the bundle

**B.** Today `build.sh` *builds* `Render` but never runs it, and `ci.yml` runs
it in a separate step **after** the bundle exists and `LoadTest` has passed.
After §7's reorder, `Render` — AppKit, `NSView`, `cacheDisplay` — sits ahead of
the bundle's existence. That partly undoes the reason `ci.yml` is split into two
jobs at all, and adds offscreen frame rendering to every build.

**Fix.** Generate the thumbnails from `StarfieldEngine` alone, the way the SVGs
and `EngineTests` already are, rather than by driving the view. §7's own stated
rule — "generated from `StarfieldEngine` with a fixed seed" — is satisfied
either way, and this keeps the framework-free property the repo values. At
minimum, name the tradeoff in the document.

### 10. `--thumbnail <dir>` would dump `single.png` and `trails.png` into the signed bundle

**B.** `Tools/Render/main.swift` is top-level code: it writes `single.png` and
`trails.png` into `outDir` **before any flag is consulted**. Point
`--thumbnail` at `Contents/Resources` and both land in the shipped, signed
bundle.

Separately, the existing flag idiom
`args.firstIndex(of: "--svg").map { args[$0 + 1] }` traps on out-of-bounds when
the flag is last; a `--thumbnail` copied from that pattern inherits the crash.

**Fix.** Restructure `Render`'s main into explicit modes. Have `build.sh`
render into a scratch directory and copy only the two thumbnails in.

### 11. The test suite structurally cannot catch what is most likely to break

**B.** The four cases in §4 exercise plain files under a fake `HOME`. They never
touch cfprefsd (finding 1), never touch a real `ScreenSaverDefaults` domain
(finding 5), and never exercise selected-saver detection. Sharpest of all: the
`--all-users` test seam means **`/Library/Screen Savers` is the one string in
the script that is never executed** — and a typo in the production default is
precisely the bug the seam hides.

**Fix.** Assert the seam's default literal directly against the script source,
and add the opt-in non-hermetic preferences test from finding 2.

---

## LOW

### 12. The versioned zip folder bakes a path that goes stale every release

**Both.** `Starfield-1.1.0/` means the install instructions need editing at each
version. §8 lists "update the round-trip check" but **not the release-notes
body** — the text users actually follow, which currently names
`Starfield.saver` at the archive root in two places in `release.yml`'s heredoc.

**Fix.** Stage as an unversioned `Starfield/` and keep the version in the zip
filename only. Update the notes heredoc explicitly.

### 13. Executable bits

**Both; B confirmed** the bit survives `ditto -c -k` and both `ditto -x` and
`unzip`. But `uninstall.sh` must be **committed** mode `100755` or the zip ships
a non-executable script and the `.command` wrapper's `./uninstall.sh` fails.
Only `build.sh` and `Tools/pe-imports.py` are `755` today.

### 14. The `.command` quarantine claim is asserted as fact and was never measured

**B, explicitly could not test.** §4 states a downloaded `.command` "is
quarantined exactly like the saver, so the first run needs right-click → Open."
A quarantined *shell script* is not the same case as a signed bundle, and recent
macOS has been removing the right-click→Open bypass in favour of Privacy &
Security → Open Anyway. This is the only entry point non-terminal users have,
and it is the one claim in the plan marked as fact that should be marked
unverified.

### 15. Thumbnail aspect ratio

**A.** 90×58 is a ratio of 1.5517 — neither 16:9 nor 4:3. The plan never says to
render at that aspect, so a frame rendered at the view's ratio and scaled down
will stretch the stars into rectangles. In a project whose entire premise is
that the stars are *square* because the original used `PatBlt`, that is a
conspicuous thing to get wrong. Render at the target aspect directly.

### 16. Smaller contradictions and omissions

- **§9 says "Six commits" then lists 0–5 where step 0 is "No commit"** — five.
- **§10's claim that "nothing in this project ever installs to `/Library`"** is
  shakier than stated: the README's *first* recommended install is
  double-clicking the `.saver`, historically a route by which copies land in
  `/Library/Screen Savers`. (Speculative on macOS 14+.) `--all-users` may be
  less exotic than the risk section assumes.
- **`Resources/Uninstall Starfield.command` sits in a directory meaning "bundle
  content"** — `Resources/` holds exactly one file, `Info.plist`, which
  `build.sh` copies into `Contents/`. Finding 6 resolves this by bundling it
  deliberately.
- **§8 misses documentation it invalidates:** `CLAUDE.md` says `build.sh`
  "builds three tools and runs two of them" and documents `Render`'s usage
  line — the plan falsifies both.
- **Symlinked installs.** A developer with
  `ln -s build/Starfield.saver ~/Library/"Screen Savers"/` meets a guard that
  validates the path suffix and then `rm -rf`s it. Removing the symlink is
  correct; an explicit `-h` check makes it deliberate rather than lucky.

---

## What this changes

Three structural amendments, the rest local:

1. **Removal order inverts** (finding 1). Restart the host *first*, then
   `defaults delete`, then `rm`, then `killall cfprefsd`.
2. **Thumbnails come from the engine, not the view** (finding 9), which removes
   the build reorder's dependency on AppKit and most of finding 10 with it.
3. **The uninstaller ships inside the bundle** (finding 6), so it survives the
   download being deleted.

And one that is really a correction to the plan's own standard of evidence:
findings 2, 5 and 11 together mean the proposed test suite would have passed
while the uninstaller silently failed to remove anything on a machine where the
screen saver was running. The plan's tests verified the half that was easy to
verify.

---

## Open, and not resolved by this review

- **AING-0003 §9 step 0 is still unanswered.** A bundle carrying test
  thumbnails (magenta, 90×58 and 180×116) has been built, signed and installed
  to `~/Library/Screen Savers/`, and `legacyScreenSaver` restarted. Whether
  System Settings actually displays it **requires a human to look** and has not
  been reported yet. Everything in §7 still rests on it.
- That installed bundle is **out-of-band state**: deliberate, uncommitted, and
  not produced by `build.sh` as it stands. Reviewer B independently noticed it
  on disk and correctly flagged it as unexplained. It should be reconciled — by
  finishing step 0 and reinstalling a clean build — before implementation
  starts.
