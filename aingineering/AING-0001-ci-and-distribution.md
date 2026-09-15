# Plan: automated builds and distribution

Status: **decided and partly implemented.** The research and recommendations
below stand as written; the answers they were waiting on are recorded in
"Decisions taken" immediately after this, and §7 has them in full.

Lives in `aingineering/` as AING-0001. The folder question that once blocked
this document is settled in `AING-0002-folder-naming-options.md`.

### Decisions taken

| Question | Answer |
|---|---|
| Deployment target | **13.0** — the verified floor for a clean link |
| Universal or arm64-only | **arm64-only**; `build.sh` keeps an `ARCHS` array so universal is a one-word change |
| $99/year Apple Developer Program | **Deferred.** Releases ship unsigned for now, so §4 and Phase 5 are unbuilt |
| Repository visibility | **Public**, MIT-licensed. This reverses the costing in §3 |
| Tests before CI | **Yes** — `Tools/EngineTests` landed first, as §6 Phase 2 argued |

Two sections below were written under the assumption that the repository was
private and are corrected in place: §3's cost analysis, and its parenthetical
about the copyright caution.

Everything in §1 and §2 was verified on this machine; the exact commands and
their output are in the appendix. Everything about GitHub's runners and about
Apple's notarization service is from knowledge, not tested here, and is marked
where it matters.

---

## 0. The short answers

| Your question | Answer |
|---|---|
| Can we automate builds? | Yes, GitHub Actions. The build already needs no Xcode project, so it is a short workflow. |
| Build for several macOS versions? | You do not need to. **One** binary serves every supported version. |
| Do we need several builds? | No — but for a *different* reason than you might expect. One build, two CPU architectures fused into one file. |
| Which macOS versions are compatible? | Recommend **macOS 13+**. Verified: that is the lowest target that builds cleanly with no extra toolchain. |
| How do we ship an installer? | A signed, notarized `.pkg` is the best user experience. A plain `.zip` works and costs nothing. The difference is $99/year. |

The one genuinely surprising finding is in §2: the current deployment target of
`14.0` was a number I picked arbitrarily, and lowering it is not free — below
macOS 13 the Swift compiler starts demanding back-deployment libraries.

---

## 1. Why one build is enough — and where the real split is

Two different things get confused under "build for several macOS versions".

### Deployment target: one build covers a range

A Mach-O binary records a **minimum OS version** (`LC_BUILD_VERSION` → `minos`).
Build once with `minos 13.0` and the result runs on macOS 13, 14, 15, 26 and
onward. You do **not** produce one build per OS release. Newer APIs are weakly
linked, so a binary can be compiled against the macOS 27 SDK and still run on
13 — which is exactly what this project does today.

So the OS-version axis needs **one** build.

### CPU architecture: this is the real split

Apple Silicon is `arm64`; Intel Macs are `x86_64`. The current build is
**arm64 only**, so it would simply not load on an Intel Mac.

The usual "Rosetta will handle it" intuition **does not apply to plugins**.
Rosetta 2 translates whole processes. A screen saver is loaded into the
system's `legacyScreenSaver` host, and a process can only load plugin code
matching its own architecture. On Apple Silicon that host is arm64 and needs
an arm64 slice; on Intel it is x86_64 and needs an x86_64 slice. Neither can
substitute for the other.

The fix is a **universal binary** — a single file containing both slices,
fused with `lipo`. Verified working on this machine:

```
archs: x86_64 arm64
  arm64     minos 13.0
  x86_64    minos 13.0
OK: loaded, principalClass = StarfieldView
OK: instantiated StarfieldView, hasConfigureSheet = true
```

So: **one artifact**, built on one runner, covering both architectures and
every macOS from the deployment target upward. No matrix needed for the build.

A matrix is still useful for *testing*, which is §3.

---

## 2. Which macOS versions — and the cost of going lower

`build.sh` currently targets `14.0`. I chose that number with no analysis
behind it. Probing the real floor produced a clean result:

| Deployment target | Links with Command Line Tools alone? |
|---|---|
| 15.0 | yes |
| 14.0 | yes (current) |
| **13.0** | **yes — lowest clean target** |
| 12.0 | no — wants `swiftCompatibility56`, `swiftCompatibilityPacks` |
| 11.0 | no — also wants `swiftCompatibilityConcurrency` |

Below macOS 13 the compiler emits references to Swift **back-deployment
compatibility archives**: static libraries that patch older Swift runtimes
shipped in older macOS releases.

Those archives do exist in the Command Line Tools, at
`/Library/Developer/CommandLineTools/usr/lib/swift/macosx/`. Two separate
problems arise, and they have different answers:

1. **`clang` does not search that directory.** When `swiftc` drives the link
   it adds the path itself; this project links with `clang -bundle`, so it does
   not. Adding `-L .../usr/lib/swift/macosx` fixes the **arm64** build at 11.0.
   Verified.
2. **Those archives are `arm64`/`arm64e` only.** The Command Line Tools ship a
   host-only toolchain, so there is no `x86_64` slice, and the Intel half of a
   universal build at 11.0 cannot link at all. Verified: it fails with
   `symbol(s) not found for architecture x86_64`.

Full Xcode ships both architectures, so a GitHub runner *could* build for 11.0
where this machine cannot. The question is whether it is worth it.

### Recommendation: target 13.0

- It is the lowest target needing no special flags, no extra `-L`, and no
  toolchain beyond what is already installed.
- macOS 13 Ventura is from 2022. Machines older than that are mostly Intel
  models already past Apple's support window.
- Dropping to 11.0 buys Big Sur and Monterey at the cost of a more fragile
  build that only works with full Xcode. That is a poor trade for a screen
  saver.

`Info.plist`'s `LSMinimumSystemVersion` must be changed from `14.0` to match.

### What is genuinely untested

Honesty about the limits of the above: **building for 13.0 is not the same as
working on 13.0.** Everything verified here was verified on macOS 26. In
particular:

- macOS 14 restructured the screen saver system (the `legacyScreenSaver` host).
  This port has only ever run under the new arrangement. Whether it behaves on
  macOS 13's older host is unknown.
- The multi-monitor behavior noted in `docs/NOTES.md` is likewise untested.

CI can reduce this uncertainty but not eliminate it — see §3.

---

## 3. GitHub Actions

### Cost, first

**This repository is public** (made so on 2026-09-15, MIT-licensed). Cost is
therefore not a constraint at all:

- Public repos get unlimited free Actions minutes, macOS runners included.
- Private repos draw on a monthly quota, and **macOS runners bill at 10× the
  Linux rate** — a five-minute macOS job costs 50 minutes against a 2,000
  minute free tier, or roughly 40 builds a month.

The restraint this section originally argued for — build only on `main` and on
tags — is unnecessary. `ci.yml` builds on every push and every pull request,
across a matrix of runner versions, because the minutes are free and the
macOS-version coverage is the one thing this project most lacks.

(The history here is worth keeping straight, because it reversed twice: the
repository was private when this document was written, having been called
public in error before that, and is now genuinely public by a later deliberate
choice. The copyright caution about `docs/NOTES.md` and `ssstars.scr`, which a
private repo did defuse, is therefore live again — it is addressed by the scope
note in `README.md` rather than by restricting access. No Microsoft code is
redistributed: `bin/ssstars.scr` remains gitignored and nothing in the build
reads it.)

### Runner selection

The build cross-compiles, so **one runner produces both architectures**. An
Apple Silicon runner is the right default.

Runner labels change over time and my information has a cutoff, so confirm
current labels against `actions/runner-images` before writing the workflow.
As of what I know:

| Label | Architecture | Note |
|---|---|---|
| `macos-13` | x86_64 (Intel) | the last Intel runner |
| `macos-14` | arm64 | |
| `macos-15` | arm64 | |
| `macos-latest` | moves between releases — **pin explicitly**, never use for releases |

### Two workflows, not one

**`ci.yml`** — on push and pull request:

1. `./build.sh`
2. Run the engine-only tests (see below)
3. Regenerate `docs/assets/*.svg` and `git diff --exit-code` them, so the README
   images can never silently drift from the simulation
4. Load-test the built bundle

**`release.yml`** — on tag `v*`:

1. Build universal (both slices, `lipo`)
2. Sign with Developer ID, notarize, staple (§4)
3. Package (§5)
4. Attach to a GitHub Release

### What can actually be tested in CI

A screen saver cannot be *watched* by a CI job, but more is testable than it
first appears — and the engine/view split this project already has is what
makes it possible.

| Test | Needs a GUI session? | Confidence |
|---|---|---|
| `build.sh` completes | no | certain |
| `StarfieldEngine` behavior — projection, respawn, clamps, RNG sequence | **no** — pure integer code, no AppKit | certain |
| SVG regeneration matches committed files | no | certain (fixed seeds) |
| Bundle loads, `NSPrincipalClass` resolves, `animateOneFrame` runs | probably | **needs verification** |
| Offscreen PNG render via `cacheDisplay` | probably | **needs verification** |

The last two instantiate an `NSView`, which historically needs a connection to
the WindowServer. GitHub's macOS runners do run in a session capable of UI
testing, so these likely work — but it should be proven in a throwaway
workflow run before the CI design depends on it.

**Mitigation if they fail headlessly:** the engine tests still cover all the
recovered arithmetic, which is the part that could actually regress. The view
is thin. This is a good argument for the split being worth having.

There are no tests today. Writing engine tests is a prerequisite for CI having
any value beyond "it compiles".

### Testing across OS versions

Separate from the build: a matrix over `macos-13` / `macos-14` / `macos-15`
running the load test would give real evidence about the compatibility claims
in §2 — the thing currently taken on faith. At 10× billing, restrict this to
tags or a manual trigger.

---

## 4. Signing and notarization

This is the part that costs money, and it is worth being blunt about the
trade.

### What exists today

`build.sh` signs **ad-hoc** (`codesign --sign -`). That seals the code against
tampering but ties it to no identity. It is enough to run on the machine that
built it. It is **not** enough for anything downloaded: files fetched by a
browser carry a quarantine flag, and Gatekeeper refuses ad-hoc-signed
quarantined code.

### What distribution requires

1. **Apple Developer Program — $99/year.** No way around it for
   Gatekeeper-clean distribution.
2. **Developer ID Application** certificate — signs the `.saver`.
3. **Developer ID Installer** certificate — only if shipping a `.pkg`.
4. **Notarization** — upload to Apple, who scan it and return a ticket:
   ```sh
   xcrun notarytool submit Starfield.zip --key AuthKey.p8 \
       --key-id "$KEY_ID" --issuer "$ISSUER_ID" --wait
   ```
   An App Store Connect API key is preferable to an Apple ID password in CI.
5. **Stapling** — attach the ticket so it validates offline:
   ```sh
   xcrun stapler staple Starfield.pkg
   ```
   Stapling a `.pkg` or `.dmg` is well-trodden. Stapling a bare `.saver`
   bundle is something I am **not certain** works; if it does not, the ticket
   still validates online, but shipping a stapled `.pkg` sidesteps the question
   entirely.

CI secrets needed: the `.p12` certificate base64-encoded, its password, a
keychain password, and the API key. The workflow creates a temporary keychain,
imports the certificate, builds, then deletes the keychain.

### The honest alternative

If $99/year for a starfield is not appealing — a reasonable position — ship an
unsigned or ad-hoc `.zip` and document the one-time workaround:

```sh
xattr -d com.apple.quarantine ~/Library/"Screen Savers"/Starfield.saver
```

or right-click → Open. For a project shared with a handful of people who can
read a README, this is fine. It is a bad experience for strangers.

**Recommendation:** start unsigned. Add signing only if you decide to publish
it properly. Structure `release.yml` so signing is a conditional step that
activates when the secrets exist, rather than a rewrite later.

---

## 5. Packaging

| Format | User experience | Notarization | Verdict |
|---|---|---|---|
| **`.zip` of the `.saver`** | download, unzip, double-click | staple uncertain | simplest; right for unsigned |
| **`.dmg`** | mount, double-click | staples cleanly | prettiest, most work |
| **`.pkg`** | double-click, installer runs, done | staples cleanly | **best UX**, needs the Installer cert |

A `.pkg` can install to `~/Library/Screen Savers` without admin rights:

```sh
pkgbuild --component Starfield.saver \
         --install-location "$HOME/Library/Screen Savers" \
         --identifier com.ilirium.Starfield --version 1.0 Starfield.pkg
```

(A per-user install location in a `.pkg` has a wrinkle — `$HOME` resolves at
build time, not install time — so a real per-user installer typically installs
to `/Library/Screen Savers` system-wide, or uses a postinstall script. Worth
checking before committing to this route.)

**Recommendation:** `.zip` now, `.pkg` if and when you sign.

---

## 6. Proposed sequence

Phased, so each step is independently useful and nothing is wasted if you stop.

**Phase 1 — make the build reproducible and multi-arch** (no CI yet)
- Add `ARCHS` and `MIN_MACOS` variables to `build.sh`; default universal, 13.0
- Two `swiftc`/`clang` passes, fuse with `lipo`
- Update `LSMinimumSystemVersion` to `13.0`
- Verify the universal bundle still loads locally

**Phase 2 — tests worth running**
- `Tests/` with engine cases: projection, size ramp, respawn, clamps, and a
  fixed-seed RNG sequence pinned against the recovered LCG
- No AppKit, so it runs anywhere
- A make/script target to run them

**Phase 3 — `ci.yml`**
- Pinned Apple Silicon runner, on push to `main` and PRs
- build → engine tests → SVG drift check
- Add the bundle load test, and find out whether it survives headless

**Phase 4 — `release.yml`**
- Tag-triggered, universal build, `.zip`, GitHub Release
- Unsigned initially; signing as a conditional block

**Phase 5 — signing, only if you want public distribution**
- Developer ID, notarization, stapling, `.pkg`

**Phase 6 — optional**
- OS-version test matrix on tags, to replace assumption with evidence

---

## 7. Decisions, as taken

Answered 2026-09-15. The questions are kept with their answers, because the
reasoning above is only legible against what was being asked.

1. **Deployment target** — 13.0 as recommended, or Intel/Big Sur support?
   → **13.0.** `MIN_MACOS` in `build.sh`, and `LSMinimumSystemVersion` in
   `Info.plist`. Below 13.0 the link wants back-deployment archives that ship
   arm64-only; the appendix has the failure output.

2. **Universal or arm64-only?** → **arm64-only.** `build.sh` still loops over
   an `ARCHS` array and runs `lipo`, which is a no-op at one architecture, so
   going universal later means adding `x86_64` to one line and nothing else.
   The cost of this choice is that Intel Macs are unsupported despite the
   cross-compilation being verified to work.

3. **$99/year?** → **Deferred, not refused.** §4 and §5 stay unimplemented.
   Releases, when they happen, ship unsigned, which means Gatekeeper requires
   the right-click-Open dance on first install. Revisit if the project gets
   users who are not you.

4. **Is the repo staying private?** → **No.** It is public and MIT-licensed as
   of 2026-09-15. §3 is corrected accordingly; the workflow is deliberately
   unfrugal as a result.

5. **Tests first?** → **Yes.** `Tools/EngineTests` was written before `ci.yml`,
   so the workflow gates on behavior rather than on compilation. This was the
   right call: see the list in §6 Phase 2 against what the suite actually
   covers.

### Still open

- **Whether AppKit view instantiation survives a headless runner.** `LoadTest`
  and `Render` both construct an `NSView`. CI is the experiment; if they fail,
  the engine tests still cover every piece of arithmetic that can regress, and
  the two AppKit gates get an `if: runner.environment == 'self-hosted'` or a
  virtual framebuffer.
- **Phase 5 packaging** (`.pkg` per-user install semantics, whether `stapler`
  accepts a bare `.saver`) — untested, and blocked on question 3 anyway.

---

## Appendix: what was actually verified

On macOS 26.6.2, Command Line Tools only, SDK 27.0.

**Cross-compilation to Intel works:**
```
$ swiftc -target x86_64-apple-macosx11.0 -emit-object -o x86.o Sources/*.swift
$ lipo -archs x86.o
x86_64
```

**Deployment-target floor for a clean link (arm64):**
```
11.0   FAILS -> needs 'swiftCompatibility56' 'swiftCompatibilityConcurrency' 'swiftCompatibilityPacks'
12.0   FAILS -> needs 'swiftCompatibility56' 'swiftCompatibilityPacks'
13.0   links OK
14.0   links OK
15.0   links OK
```

**The archives exist but are arm64-only:**
```
libswiftCompatibility50.a                arm64 arm64e
libswiftCompatibilityConcurrency.a       arm64 arm64e
libswiftCompatibilityPacks.a             arm64 arm64e
```

**Adding the toolchain path fixes arm64 at 11.0, but not Intel:**
```
arm64    @11.0 with -L toolchain: links OK
x86_64   @11.0 with -L toolchain: FAILS: symbol(s) not found for architecture x86_64
```

**A universal 13.0 bundle builds, signs, and loads:**
```
archs: x86_64 arm64
  arm64     minos 13.0
  x86_64    minos 13.0
OK: loaded, principalClass = StarfieldView
OK: instantiated StarfieldView, hasConfigureSheet = true
OK: animateOneFrame ran
```

Not verified, and flagged above where relied upon: GitHub runner labels and
images, whether AppKit view instantiation succeeds on a headless runner,
whether `stapler` accepts a bare `.saver`, `.pkg` per-user install semantics,
and any behavior on macOS 13–15, which were never run.
