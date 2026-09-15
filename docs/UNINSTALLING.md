# Removing a screen saver, and the caches that fight back

Deleting a `.saver` bundle looks like a one-line job. `rm -rf` the directory and
you are done.

You are not done. The settings survive in a place `defaults` cannot see, the
plist you delete comes back with its old contents, and the Screen Saver pane
goes on showing a preview of software that is no longer installed. Each of
those is a separate cache with its own rules, and none of them is documented.

This is the story of finding all three. The reference version — flags, order of
operations, guards — is `uninstall.sh` itself and
[AING-0005](../aingineering/AING-0005-uninstaller-revised.md) §3. What follows
is how it got that way, including the parts that were wrong first.

Everything here was measured on macOS 26.6.2, Apple Silicon. Claims that were
not measured say so.

## 1. Why bother

The argument for shipping an uninstaller is not that `rm -rf` is hard. It is
that a hand-written `rm` is easy to get *incomplete*, and the person most
likely to write one is the person who installed six months ago, has long since
emptied Downloads, and is now guessing at paths.

That observation decided the delivery. The script ships **inside the bundle**,
at `Contents/Resources/uninstall.sh`, where it survives the download being
deleted. It ships again in the release zip for people who still have it. And
the README carries a copy-pasteable `rm` block for people who have neither.

Two things were ruled out early, both by measurement.

**An Uninstall button in the configuration sheet is impossible.** Our code runs
inside the system's screen saver host, which is sandboxed:

```
$ codesign -d --entitlements - .../legacyScreenSaver.appex/Contents/MacOS/legacyScreenSaver
    com.apple.security.app-sandbox                                        true
    com.apple.security.temporary-exception.files.absolute-path.read-only  [...]
```

Read-only exceptions. The sheet cannot delete the bundle it is running from.

**And the host holds the executable mapped:**

```
$ lsof -p $(pgrep legacyScreenSaver) | grep Starfield
legacyScr ... txt REG ... /Users/…/Starfield.saver/Contents/MacOS/Starfield
```

which is why the script stops that process before it removes anything.

## 2. What an install actually leaves

| Path | Present |
|---|---|
| `~/Library/Screen Savers/Starfield.saver` | yes |
| `/Library/Screen Savers/Starfield.saver` | no — our README never creates it |
| `~/Library/Preferences/ByHost/com.ilirium.Starfield.<UUID>.plist` | yes |

That table was the first answer, and it was wrong by omission in two places.
Sections 4 and 5 are the two things missing from it.

**A trap worth naming, because it produces a confident wrong answer:**
`defaults domains` does **not** list ByHost domains. Their absence from that
listing is not evidence that no preferences exist. Glob the directory instead.

## 3. Deleting the plist does not delete the setting

The obvious order — remove the bundle, remove the plist, done — has a bug that
only appears when something else has the preferences domain open.

A live client holds the domain's values in `cfprefsd`. Its next write
**recreates the file, with the old values in it**:

```
$ defaults -currentHost write <probe> Density -int 77
$ # a helper opens the domain via CFPreferencesCopyValue
$ rm ~/Library/Preferences/ByHost/<probe>.*.plist      -> file gone
  read back: 77                                         <- client still sees it
  file now:  { "Density" => 77, "Touched" => 1 }        <- and it is back
```

`legacyScreenSaver` is exactly such a client, and on macOS 14+ it stays running
even while the screen is unblanked. jwz found the same thing and says so in
XScreenSaver's installer:

> As of macOS 14.0, legacyScreenSaver remains running even while the screen is
> unblanked. It might have already loaded saver bundles from a previous
> installation of XScreenSaver, so we must kill it to get it to load the new
> versions.

So the order is load-bearing: **stop the clients first**, then delete, then
flush `cfprefsd`. Not the other way round.

There is a mirror trap on the other side. `defaults -currentHost delete
<domain>` reports the domain gone but **leaves the plist on disk**. Neither
operation alone suffices, which is why the script does both.

## 4. The settings are somewhere else entirely

This is the one that would have shipped a broken uninstaller, and it was found
by reading somebody else's code.

XScreenSaver's `preinstall` script migrates preferences into a sandbox
container on 10.15 and later, with a comment explaining why:

> Savers are sandboxed as of 10.15, which means the preferences files moved.
> […] Without this, all saver preferences would be wiped by the upgrade.

Checking that claim against this machine produced two copies of the same
domain, with **different values**:

```
$ plutil -p ~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost/com.ilirium.Starfield.<UUID>.plist
{ "Density" => 200, "WarpSpeed" => 8 }      <- what the saver actually uses

$ plutil -p ~/Library/Preferences/ByHost/com.ilirium.Starfield.<UUID>.plist
{ "Density" => 120, "WarpSpeed" => 5 }      <- what unsandboxed tools wrote

$ defaults -currentHost read com.ilirium.Starfield
{ Density = 120; WarpSpeed = 5; }           <- cannot see the container at all
```

The container copy holds the settings chosen through the configuration sheet.
`defaults` cannot see it. An uninstaller that sweeps only the visible path
deletes the decoy and leaves the real thing behind.

**This is not a hypothetical.** The same machine had just had XScreenSaver
removed with Homebrew, whose `zap` stanza trashes
`~/Library/Preferences/org.jwz.xscreensaver.*.plist`. Afterwards:

```
$ ls ~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost/ | grep -c '^org.jwz'
4
$ ls ~/Library/Preferences/ByHost/ | grep -c '^org.jwz'
0
```

Four orphans in the container, none outside it. The glob matched nothing
because the real files were never there. A widely installed, well maintained
project ships this bug, and ours was about to.

## 5. The cache that nothing invalidates

The third cache is the strangest, and it is why `--refresh-preview` exists.

System Settings renders the Screen Saver pane's tiles through
`WallpaperLegacyExtension.appex`, which keeps them here:

```
$(getconf DARWIN_USER_CACHE_DIR)com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails/
```

Note the location. It is under `/var/folders`, **not** `~/Library/Caches`, so a
survey that checks the obvious place finds nothing and reports that nothing
exists.

Entries are keyed per module and the key is stable: after clearing the
directory and letting it repopulate, all 13 regenerated filenames were ones
already present in the pre-clear backup. Zero were new.

What does **not** invalidate an entry, tested in escalating order, each time
with the cache untouched and the pane reopened:

| Attempt | Bundle on disk | Cached tile | |
|---|---|---|---|
| Add thumbnails to the live bundle, re-sign | magenta | old tile | not invalidated |
| Replace the bundle wholesale (`rm -rf` + `cp -R`), re-signed | green | magenta | not invalidated |
| Same, plus `CFBundleShortVersionString` 1.0.0 → 1.1.0 and `CFBundleVersion` 1 → 2 | green | magenta | **not invalidated** |

The extension was not merely asleep. In the third attempt a *freshly spawned*
process re-enumerated the modules twice —

```
Load Screen Saver Modules
Completed discovery. Final # of matches: 13
```

— logged no thumbnail error at all, and served the tile it had cached forty
minutes earlier.

**There is no supported way to invalidate it.** The extension binary contains
exactly three `com.apple.*` strings — `com.apple.wallpaper`,
`com.apple.wallpaper.choice.screen-saver`, and the cache name. No notification,
no refresh selector. The key is not a hash of the bundle path, identifier, or
name; eight spellings were tried and none matched. So a single entry cannot be
targeted: it is the whole directory or nothing.

XScreenSaver has no answer to this either. Nothing in jwz's installer or in
Homebrew's uninstaller touches `/var/folders`. That is not proof that no
mechanism exists, but it is the strongest evidence available that none is
known.

## 6. So `--refresh-preview`, and only that

Removing the files is the only lever, which leaves the question of who pulls it.

A plain `./uninstall.sh` **deliberately does not**. Clearing every other
saver's tile is not what somebody removing one saver asked for, and it would
widen the script past the two path shapes it is otherwise allowed to touch. The
accepted cost is that an uninstall leaves a ~30 KB orphan, and that someone who
uninstalls and reinstalls sees a stale tile until they ask for a refresh.

The flag does it explicitly, under the same guards as everything else: only
names matching `[0-9a-f]{64}\.png`, only inside that one directory, with the
path reached through `getconf` rather than hardcoded.

The blast radius is a regenerable cache. That was demonstrated rather than
assumed — after clearing all 301 entries, the next time the pane opened it
rebuilt 13 of them, one per discovered module.

## 7. Testing something whose job is to delete

The suite had one hard constraint. **`cfprefsd` ignores `HOME`:**

```
$ HOME=/tmp/fakehome defaults -currentHost read com.ilirium.Starfield Density
120                                       <- the real value

$ HOME=/tmp/fakehome defaults -currentHost write <probe> K -int 1
  in fake home:  total 0
  in real home:  <probe>.….plist          <- wrote to the REAL home
```

Fixing §3 requires calling `defaults`. So the obvious test design — run the
script under a throwaway `HOME` — would **delete the developer's real screen
saver preferences while reporting success**.

Hence the seam: six overridable directories, and overriding any of them puts
the script in *hermetic mode*, where it touches files only and skips every
`defaults`, `cfprefsd` and `killall` call. The destructive path gets tested;
nothing reaches around the test into the real user's preferences.

That seam has a cost worth stating: the real directory literals are then the
one thing hermetic mode never executes, and a typo in one is exactly the bug
the seam hides. They are asserted against the script's source text instead. So
is the root refusal, because `EUID` is readonly in bash and cannot be faked.

## 8. What the tests found that reading had not

Four things, none of which review had caught.

**macOS ships bash 3.2.** Expanding an empty array under `set -u` is an
unbound-variable error there, fixed only in bash 4.4. `--keep-settings`
aborted on it, because that path legitimately collects zero plists. Every array
expansion in the script is now `${ARR[@]+"${ARR[@]}"}`.

**The self-deletion re-exec dropped its arguments.** The bundled copy has to
delete the file it is executing, so it re-execs from `$TMPDIR` first. That
re-exec passed `"$@"` — *after* the option-parsing loop had consumed it with
`shift`. An unattended `-y` run therefore stopped at a confirmation prompt with
nobody there to answer. It was found by a test timing out after two minutes.
The arguments are now captured before parsing, and a test fails if they stop
being carried.

**APFS is case-insensitive by default.** One cache decoy was the same 64
characters in uppercase, to prove the lowercase-only pattern would spare it. It
did not survive — because it was never a separate file. The test was wrong, not
the script; the decoys are now a 63-character name and a 64-character name with
one non-hex letter.

**`rm -rf` on a symlink removes the link, never the target.** The symlink case
passed even with the `-L` branch disabled, which means that branch is
explanatory rather than load-bearing. The test now checks that the script
*said* it removed a symlink, instead of an outcome that held either way.

## 9. Mutation testing

A suite that cannot fail is decoration. Nine mutations were applied to
`uninstall.sh` and the suite re-run against each. Seven were killed: dropping
the container sweep, dropping `nullglob`, loosening the cache pattern, dropping
the bundle identity check, dropping the render scratch-domain sweep, dropping
the dry-run early exit, and dropping the root refusal.

Two survived, and both are **redundant guards** rather than gaps:

- `--keep-settings` is honoured twice, at collection and again at removal.
  Defeating either alone changes nothing.
- `valid_bundle_path` cannot fire today, because bundle paths are *constructed*
  from the two known directories rather than discovered. It is there for a
  future in which they are not.

Neither is worth contorting a test to kill. If either guard ever becomes the
only one, that note is wrong and the mutation should be re-run.

## 10. One borrowed idea

Homebrew's generated XScreenSaver uninstaller identifies bundles by reading
each `Info.plist` and matching `CFBundleIdentifier == org.jwz*`, rather than by
trusting the filename. That survives a renamed bundle; a path check does not.

Ours now does both — the path must be exactly `<known dir>/Starfield.saver`,
*and* the bundle must admit to being `com.ilirium.Starfield` before it is
removed. A saver that merely shares our name is refused out loud.

## What is still unverified

- **Whether `defaults -currentHost delete` can reach the container domain.** It
  cannot *read* it; deletion was never tried. If it cannot, removal there is
  file-only and §3's ordering matters more, not less.
- **How long a stale tile-cache entry survives on its own.** `/var/folders` is
  cleaned periodically, so the staleness is presumably not permanent — but the
  interval was never measured, and "it fixes itself eventually" is not a
  shipping story.
- **`--all-users`.** Nothing in this project creates
  `/Library/Screen Savers/Starfield.saver`. The flag is kept because
  XScreenSaver's installer does write there, and because the README's first
  recommended install hands the bundle to System Settings, historically a route
  by which copies land system-wide.
- **The `.command` wrapper's quarantine behaviour.** A downloaded shell script
  is not the same case as a signed bundle, and recent macOS has been narrowing
  the right-click-Open bypass. It needs Finder, Terminal, and a genuinely
  downloaded file, so CI cannot exercise it.

## Summary of method

Probe the platform rather than cite it. Read the code of somebody who has been
fighting the same platform for a decade. Test the thing that deletes, in a way
that cannot reach the real user's data. Then mutate the script and check the
tests notice.

Three of the findings here — the container preferences, the re-exec argument
loss, and bash 3.2 — were invisible to reading and obvious to running.
