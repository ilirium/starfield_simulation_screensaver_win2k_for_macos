# Step 0's answer, and the two gaps it uncovered

Status: **findings confirmed; `--refresh-preview` decided and scheduled.**
Written 2026-09-15,
against `aingineering/AING-0005-uninstaller-revised.md` as of commit `41d7322`.

Amends [AING-0005](AING-0005-uninstaller-revised.md) §1, §3, §4 and §5. That
plan stands unedited, per the convention that a revision gets its own number —
the delta is the useful part. Nothing here changes the plan's shape: the
uninstaller, the thumbnail and the `Render` fix all remain the right things to
build.

Step 0 passed. Getting there turned up two things the plan does not know about,
and **the second is the serious one**:

1. A **tile cache** that nothing about the bundle invalidates (§2, §3, §6).
2. The saver's real preferences live in the **sandbox container**, not where
   §1 measured them — so the uninstaller as planned would leave them behind,
   and §4's premise is mis-scoped (§7).

Measured on macOS 26.6.2, Apple Silicon, with the commands shown.

---

## 1. Step 0 passed

**`Contents/Resources/thumbnail.png` / `thumbnail@2x.png` is still honoured for
third-party legacy savers.** AING-0005 §5 proceeds as written.

The check was the one §7 specified: garish magenta placeholders (90x58 and
180x116, white bar across the middle) hand-added to the *installed* bundle and
re-signed, then look at the Screen Saver pane.

It very nearly returned the wrong answer. The pane showed a generic cyan swirl,
which reads as "the convention is dead" — and it was **a stale cache**, not a
dead convention. Believing the tile would have replanned §5 for no reason.

---

## 2. The cache

`WallpaperLegacyExtension.appex` renders the pane's tiles and caches them:

```
$(getconf DARWIN_USER_CACHE_DIR)com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails/
```

Content-addressed filenames, `<64 hex>.png`. Note the location: **`/var/folders`,
not `~/Library/Caches`** — see §4.

### What was measured

| Claim | How |
|---|---|
| Cache keys are **stable per module** | after clearing, all 13 regenerated keys were filenames already present in the pre-clear backup; 0 brand-new |
| The key is **not derived from bundle path, id, or name** | SHA-256 of eight spellings (path, path+`/`, `file://` forms, `com.ilirium.Starfield`, `Starfield`, `Starfield.saver`, the thumbnail's own path, and with a trailing newline) — none matched the key |
| A read `thumbnail@2x.png` yields a **180x116** tile; anything else lands at **214x130** | of 13 fresh tiles, 3 were 180x116 and 10 were 214x130; Starfield moved 214x130 -> 180x116 the moment its thumbnail was honoured |
| Source bytes are **not** what is cached | neither our thumbnail's hash nor `Random.saver`'s appears in the cache; sampled tiles have rounded corners, so tiles are recomposed |

The two size buckets are the cheap oracle: **180x116 means the bundle's
thumbnail was read; 214x130 means it was not.** That is the whole of what was
measured, and it is enough to check the feature.

**Not established: what the 214x130 tiles actually are.** "Generic fallback" is
the obvious guess and it is wrong, or at least unproven — all ten are *distinct*
images, and the cyan swirl Starfield showed matches no other tile byte-for-byte
(300 distinct images across the 301-file pre-clear backup). So they are not
copies of one shared placeholder. Whether they are per-module renders, assigned
placeholders, or something else was not determined, and nothing in this plan
depends on the answer.

### What does not invalidate it

Three escalating attempts, each with the cache deliberately untouched and the
pane reopened:

| Attempt | Bundle on disk | Cache tile | Verdict |
|---|---|---|---|
| Add thumbnails to the live bundle, re-sign | magenta | cyan swirl, 214x130 | not invalidated |
| Replace the bundle wholesale (`rm -rf` + `cp -R`), re-signed | green | magenta, unchanged mtime | not invalidated |
| Same, plus `CFBundleShortVersionString` 1.0.0 -> 1.1.0 and `CFBundleVersion` 1 -> 2 | green | magenta, unchanged mtime | **not invalidated** |

The extension was not merely asleep. In the first attempt it logged
`Load Screen Saver Modules` / `Completed discovery. Final # of matches: 13`
twice while the magenta files sat on disk, with **no** `Could not load thumbnail
for legacy screen saver` error. In the third, a *freshly spawned* process
(a new pid, after System Settings was quit) re-enumerated twice more and still
served the 13:43 tile.

**Only clearing the cache directory refreshes the tile.** Confirmed: after
`rm -f <dir>/*.png` plus `killall WallpaperLegacyExtension WallpaperAgent
Wallpaper legacyScreenSaver` and quitting System Settings, the pane rendered
magenta and the cache held 13 fresh entries — one per discovered module.

---

## 3. Why this matters: the upgrade path

Every existing v1.0.0 install is at a path that already has a cache entry,
written when the bundle had no thumbnail. §2 shows that entry survives the
upgrade.

**So v1.1.0 ships its new thumbnail and existing users keep seeing the generic
swirl.** New installs on machines that never had Starfield are unaffected —
there is no entry to be stale. This is precisely the population the feature is
*least* visible to and the one most likely to look.

**Unverified:** how long the entry survives on its own. `/var/folders` is
subject to periodic cleanup, so the staleness is presumably not permanent, but
nothing here measured the eviction interval, and "it fixes itself eventually"
is not a shipping story.

---

## 4. Amendment to §1 — the footprint survey is incomplete

§1 states the install leaves "Nothing else: no `~/Library/Caches` entry, no
`Application Support`, no LaunchServices registration worth undoing."

It misses two locations. Both are the same class of error as §1's own existing
trap note about `defaults domains` not listing ByHost domains — **absence from
the place you looked is not absence.**

| Missing from the table | Where |
|---|---|
| The tile cache | `$(getconf DARWIN_USER_CACHE_DIR)com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails/` — `/var/folders`, which is why "no `~/Library/Caches` entry" is true and useless |
| **The sandbox container preferences** | `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost/` — see §7 |

## 5. Amendment to §3 — should the uninstaller clear it?

It does not today; §3.2's seven steps never mention the cache.

**The key cannot be computed** (§2), so an uninstaller cannot delete just its
own entry. The only options are all-or-nothing.

| Option | For | Against |
|---|---|---|
| **A. Clear the whole directory** | fixes uninstall-then-reinstall; proven regenerable — all 13 tiles came back on the next pane open | discards 12 other savers' tiles; widens the blast radius past §3.3's two permitted path shapes; needs a 4th hermetic override |
| **B. Leave it, document it** | keeps §3.3's tight rules intact | an orphan entry survives; a reinstall serves a stale tile |

**Decided 2026-09-15: B — the normal uninstall run does not touch the cache.**
Clearing happens only behind the explicit `--refresh-preview` flag (§9).

This keeps §3.3's rule intact: a plain `./uninstall.sh` still removes only the
two permitted path shapes, and nothing a user did not ask about. The cost is
accepted — an uninstall leaves a ~30 KB orphan in `/var/folders`, and someone
who uninstalls and later reinstalls sees a stale tile until they run the flag.
Both are recoverable; silently clearing twelve other savers' tiles during an
uninstall is not what the user asked for.

Note this is the *lesser* half of the problem. Uninstall is the rare case; §3
cannot help the upgrader at all.

---

## 6. Amendment to §5 — v1.1.0 needs a remedy for upgraders

### There is no supported invalidation mechanism

Looked for one, did not find one:

- The extension binary contains exactly **three** `com.apple.*` strings —
  `com.apple.wallpaper`, `com.apple.wallpaper.choice.screen-saver`, and the
  cache name. **No notification name, no refresh or invalidate selector.**
- Its only cache-related string is the log line `Unable to access thumbnail
  cache: %@`; the cache logic itself is elsewhere and the binary is stripped of
  anything that would name it.
- The key is not computable from the obvious module inputs (§2), so **deleting
  one entry is not possible** — it is the whole directory or nothing.
- Content change, wholesale replacement and a version bump all fail to
  invalidate (§2).

So the only lever is removing the files. The question is who pulls it and with
what guards.

### Decided: one guarded implementation (full spec in §9)

Write it **once**, as a mode of the uninstaller rather than a command pasted
into three documents that will drift apart:

```
./uninstall.sh --refresh-preview     # clears the tile cache, removes nothing else
```

It reuses the machinery §3 already requires — `set -euo pipefail`, `nullglob`,
a validated filename pattern, `|| true` on `killall` — and adds no new
concepts:

```sh
: "${STARFIELD_THUMBCACHE_DIR:=$(getconf DARWIN_USER_CACHE_DIR)com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails}"
```

- Only names matching `[0-9a-f]{64}\.png`, inside *that exact* directory, are
  removable — the same "two permitted shapes" discipline as §3.3, widened by
  exactly one shape.
- Then `killall WallpaperLegacyExtension || true`, and advise quitting System
  Settings, which caches the module list independently (§3.2 step 5).
- The fourth overridable directory puts it inside the hermetic suite, so the
  destructive path is tested like the rest.

Then the callers — **two, not three**, per §5's decision:

| Caller | Why |
|---|---|
| README, beside the install step | the upgrade path — worded so **only** upgraders run it |
| `release.yml`'s generated notes | reaches the v1.0.0 cohort, who will not re-read the README |

The normal `./uninstall.sh` run is deliberately **not** a caller (§5).

### Why this is proportionate

The blast radius is a regenerable cache in `/var/folders`. Clearing it costs
every other saver one re-render on the next pane open — and that regeneration
was **demonstrated, not assumed**: all 13 tiles came back on the next open.

It is worth being honest in the README about what the command does, rather than
presenting it as magic. The project already documents the `xattr` quarantine
workaround in exactly this spirit.

### The affected population is bounded

Only machines that already have Starfield installed carry a stale entry. A
machine that never had it has nothing to invalidate and shows the new thumbnail
immediately. That cohort is everyone who installed v1.0.0 — small, known, and
reachable through the release notes, which is the argument for putting the
command there rather than relying on the README.

### Rejected

- **Renaming the bundle** to dodge the key. It would change the saver's name in
  the pane, and it is unverified that the key even derives from the path.
- **Doing it from the saver itself.** It runs sandboxed inside
  `legacyScreenSaver` (§1), and only once the user has already selected it —
  far too late to fix the tile they pick it by.
- **Waiting for eviction.** Rests on the unmeasured interval in §3.

### How to verify the fix

Use the §2 oracle rather than looking: after the refresh, Starfield's tile
should be **180x116**. No screenshot needed, and it is scriptable.

## 7. Amendment to §1, §3 and §4 — the settings are in the sandbox container

**This is the most consequential finding in this document.** It came from
reading XScreenSaver's installer (§8), not from the cache work.

Savers have been sandboxed since macOS 10.15, and their preferences moved
accordingly. On this machine the domain exists in **two** places, with
**different values**:

| Copy | Density / WarpSpeed | Last written by |
|---|---|---|
| `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Preferences/ByHost/com.ilirium.Starfield.<UUID>.plist` | **200 / 8** | the installed saver, running sandboxed |
| `~/Library/Preferences/ByHost/com.ilirium.Starfield.<UUID>.plist` | 120 / 5 | `Render`, running unsandboxed |

```
$ defaults -currentHost read com.ilirium.Starfield
{ Density = 120; WarpSpeed = 5; }        <- the NON-container copy only
```

The container copy holds the settings actually chosen through the config
sheet. `defaults` cannot see it.

### What this breaks

- **§1's footprint table lists the wrong plist.** It names the non-container
  path as *the* settings location. That is the copy the shipped screen saver
  never reads.
- **§3.2 step 7 deletes the wrong domain.** `defaults -currentHost delete
  com.ilirium.Starfield` plus a glob of `~/Library/Preferences/ByHost` removes
  the 120/5 copy and **leaves the user's real 200/8 settings on disk** — the
  precise failure the uninstaller exists to prevent.
- **§2.1's `cfprefsd` finding still stands**, but now has to be applied to the
  container domain as well.
- **§4's premise is mis-scoped. Re-measured 2026-09-15, and confirmed.** With
  the non-container store seeded to a distinctive 77/3, a `Render` run left the
  container at 200/8 untouched and moved the non-container store to its 120/5.
  So `Render` clobbers the store the *preview harness* reads, and never the one
  the installed saver reads. The fix is still right and still worth making; the
  justification "silently overwrites the user's own Density and WarpSpeed"
  is narrowed to the preview harness.

  **Trap for whoever re-runs this:** read the value back through `defaults`,
  not `plutil` on the file. Immediately after `Render` exits the file still
  shows the old values — `cfprefsd` has not flushed — which reads as "no
  clobber happened" and is wrong. Same cause as §2.1.

### This is not theoretical

The brew uninstall of XScreenSaver, run on this machine today, left **4
orphaned `org.jwz.*` plists** in the container and **0** outside it. Homebrew's
`zap` stanza trashes `~/Library/Preferences/org.jwz.xscreensaver.*.plist` —
which matched nothing, because the real ones were never there. A well-
maintained, widely-installed project ships exactly this bug.

### What the uninstaller must do

Add the container ByHost directory as a fifth overridable path, sweep it with
the same validated UUID pattern, and treat it as the *primary* location rather
than an afterthought. Whether `defaults -currentHost delete` can reach the
container domain at all was **not** established — if it cannot, removal there
is file-only, and §2.1's live-client ordering matters even more.

---

## 8. Prior art: XScreenSaver

jwz ships ~290 savers and has been fighting this platform since 2013, so his
installer is worth reading. Recovered from the cached 6.15 DMG
(`Install Everything.pkg` -> `Scripts/preinstall`).

**On the question of invalidating the tile cache: he has no solution either.**
Nothing in the installer or in Homebrew's uninstaller touches
`/var/folders`. That is not proof none exists, but it is the strongest
available evidence that none is known.

What he does do corroborates AING-0005 independently:

| jwz does | Matches |
|---|---|
| kills `legacyScreenSaver` — *"As of macOS 14.0 [it] remains running even while the screen is unblanked. It might have already loaded saver bundles from a previous installation, so we must kill it"* | §3.2 step 5 |
| kills `System Settings` — *"it might have old saver bundles loaded into it"* | §3.2 step 5's second client, and §3.4 |
| migrates prefs into the container on 10.15+, explicitly *"Without this, all saver preferences would be wiped by the upgrade"* | §7 above — this is where the finding came from |
| `rm -rf /Users/*/Library/Screen Savers/$f` on install, to avoid per-user/system conflicts | §3's `--all-users`; his pkg installs to `/Library/Screen Savers`, which supports **keeping** the flag (AING-0005 §8 doubted it) |

Two of his comments are worth quoting against AING-0001's Gatekeeper section:
`xattr -r -d com.apple.quarantine` and `spctl --add` are both annotated
*"This trick probably doesn't work."*

**Identification by bundle id, not filename.** Homebrew's generated uninstaller
reads each `Info.plist` and matches `CFBundleIdentifier == org.jwz*` rather
than trusting the bundle's name. AING-0005 §3.3 validates by path shape
instead. His approach survives a renamed bundle; ours does not. Worth adopting
as a *confirmation* step before removal — read `CFBundleIdentifier` and require
`com.ilirium.Starfield` — rather than as a replacement for the path guards.

---

## 9. Spec: `--refresh-preview`

**Decided 2026-09-15.** Implement as part of AING-0005 §7's **commit 2**
(`uninstall.sh` and its tests); the README and release-note wording lands with
**commit 4** (packaging).

### Interface

```
./uninstall.sh --refresh-preview [--dry-run] [-h]
```

Clears the System Settings tile cache and **nothing else**. Removes no bundle,
no preferences. Mutually exclusive with `--keep-settings` and `--all-users`;
combining them is a usage error, not a silent no-op. `--dry-run` lists what
would be removed and exits 0.

### Behaviour

1. Refuse if `$EUID` is 0, for the same reason §3.3 gives — a root run leaves
   root-owned files in a user path.
2. Resolve the directory:
   ```sh
   : "${STARFIELD_THUMBCACHE_DIR:=$(getconf DARWIN_USER_CACHE_DIR)com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails}"
   ```
   This is the **fourth** overridable directory, so hermetic mode covers it.
3. If the directory does not exist, print so and **exit 0** — not an error.
4. Remove only entries matching `[0-9a-f]{64}\.png`, directly inside that
   directory. Anything else is refused loudly. `shopt -s nullglob`, per §3.3's
   trap.
5. Outside hermetic mode only: `killall WallpaperLegacyExtension || true`, and
   advise quitting System Settings, which caches the module list independently.

### Tests (`Tools/uninstall-tests.sh`)

Hermetic, via `STARFIELD_THUMBCACHE_DIR`:

| Case | Expectation |
|---|---|
| a populated directory | every `<64 hex>.png` gone |
| decoys: `notahash.png`, `ABCDEF….png` (uppercase), a subdirectory, a `.txt` | **all survive** |
| `--dry-run` | nothing removed, exit 0 |
| directory absent | exit 0, no error |
| unmatched glob | no path containing `*` reaches `rm` |
| run as root | refuses |
| combined with `--all-users` | usage error |
| **default literal** | asserted textually against the script source, since hermetic mode never executes it — the same technique §3.3 uses for `/Library/Screen Savers` |

### Verification

Use the §2 oracle, not a screenshot: after a refresh, a saver whose bundle
carries a thumbnail produces a **180x116** cache entry. Scriptable, and it does
not need a human to judge a tile.

### What this does not solve

Nothing invalidates the cache on its own (§2), so an upgrader who never runs
the flag keeps the old tile until `/var/folders` is cleaned — an interval this
document never measured. The flag is a remedy, not a fix; there is no fix to
have.

---

## 10. State of the machine

Step 0's magenta evidence is **gone** — these experiments overwrote the
installed bundle with green thumbnails and a 1.1.0 version string. That no
longer matters: step 0 is answered.

**The machine has been reconciled.** `./build.sh` was run (103 engine checks,
`LoadTest` green) and its output installed, so
`~/Library/Screen Savers/Starfield.saver` is now byte-identical to
`build/Starfield.saver` — v1.0.0, signature valid, `Contents/Resources` empty.

**One thing is still inconsistent and should be fixed:** the tile cache still
holds the magenta tile for a bundle that now contains no thumbnail at all. By
§2 nothing will correct that on its own. Clear the cache, or the pane shows
artwork that exists nowhere on disk — the same trap that nearly cost step 0 the
wrong answer.

The 200/8 container preferences (§7) were **not** touched.
