# Plan: automated builds and distribution

Status: **proposal, nothing implemented.** Research and a recommendation, for
you to approve, amend, or reject before any workflow file is written.

Living at the repository root temporarily. It moves into a working-documents
folder once that folder has a name — see `folder-naming-options.md`.

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
- The multi-monitor behavior noted in `NOTES.md` is likewise untested.

CI can reduce this uncertainty but not eliminate it — see §3.

---

## 3. GitHub Actions

### Cost, first

**This repository is private.** I said "public" twice in earlier conversation;
that was wrong, and it matters here:

- Public repos get unlimited free Actions minutes.
- Private repos draw on a monthly quota, and **macOS runners bill at 10× the
  Linux rate**. A five-minute macOS job costs 50 minutes of quota. A personal
  account's free tier is 2,000 minutes/month, so roughly 40 builds a month
  before it costs money.

That is workable but argues for restraint: build on pushes to `main` and on
tags, not on every push to every branch.

(It also means the copyright caution I raised about `NOTES.md` and
`ssstars.scr` was overstated — a private repo is not redistribution.)

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
3. Regenerate `docs/*.svg` and `git diff --exit-code` them, so the README
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
| SVG regeneration matches committed files | no | certain |
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

## 7. Decisions I need from you

1. **Deployment target** — 13.0 as recommended, or is Intel/Big Sur support
   worth the fragility?
2. **Universal or arm64-only?** Universal roughly doubles binary size (still
   trivial, ~200 KB) and costs nothing else. Do you care about Intel Macs at
   all?
3. **$99/year?** This determines whether Phase 5 ever happens, and it shapes
   Phase 4.
4. **Is the repo staying private?** If it goes public, Actions become free and
   the restraint in §3 is unnecessary.
5. **Tests first?** Phase 2 is where CI stops being decorative. I would not
   build Phase 3 without it.

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
