# The preview image, and the answer that was almost wrong

Until 1.1.0 the Screen Saver pane showed Starfield as a generic tile, because
the bundle shipped no preview image. Fixing that is a small feature with a
disproportionately interesting failure: the experiment set up to validate it
returned the **wrong answer**, confidently, and acting on that answer would
have thrown away a working design.

This is the story of the check, why it lied, and what it took to make a 90-pixel
picture of a starfield actually look like one.

Measured on macOS 26.6.2, Apple Silicon.

## 1. A convention with nothing behind it

macOS finds a legacy saver's preview by **filename**. There is no `Info.plist`
key:

```
$ find "/System/Library/Screen Savers/Random.saver" -type f
  Contents/Resources/thumbnail.png       90 x 58
  Contents/Resources/thumbnail@2x.png   180 x 116
```

`Random.saver` declares no thumbnail, preview, poster or icon key anywhere.
`FloatingMessage.saver` ships no image at all, so it is optional.

Two things made this worth checking rather than assuming. `Random.saver` is
Apple's own, and the convention predates System Settings — which was rebuilt in
macOS 14. A convention that still works for a first-party bundle may have
quietly stopped working for third-party ones.

The whole thumbnail design rested on that, so it became step 0: confirm it
before writing anything.

## 2. Step 0, and the answer it gave

The check was deliberately crude. Two garish magenta rectangles with a white
bar across the middle, at exactly 90×58 and 180×116, added by hand to the
*installed* bundle and re-signed. Nothing subtle: if the pane showed magenta,
the convention worked.

The pane showed a blue-green swirl.

That is the generic-looking tile. Read plainly, it says the convention is dead
for third-party savers, and §5 of the plan needs redesigning around some other
mechanism — or dropping.

It was wrong.

## 3. Why it lied

The tell was a string in the extension that renders those tiles:

```
$ strings -a .../WallpaperLegacyExtension.appex/Contents/MacOS/WallpaperLegacyExtension \
    | grep -i 'thumbnail\|cache'
com.apple.wallpaper.legacy.thumbnails
Could not load thumbnail for legacy screen saver: %s
Unable to access thumbnail cache: %@
```

A cache. And a stale cache looks *exactly* like a dead convention.

It lives under `/var/folders`, not `~/Library/Caches`:

```
$(getconf DARWIN_USER_CACHE_DIR)com.apple.wallpaper.extension.legacy/com.apple.wallpaper.legacy.thumbnails/
```

Clearing it, restarting the wallpaper services, and reopening the pane produced
magenta. The convention was fine all along.

Two details make this worse than an ordinary stale cache, and both are covered
in [UNINSTALLING.md](UNINSTALLING.md) §5: entries are keyed per module and
**nothing about the bundle invalidates them** — not new contents, not wholesale
replacement, not a version bump. The magenta files had been sitting on disk for
half an hour, and the pane had enumerated the modules twice in that time without
re-reading them.

The old tile, recovered from a backup of the cache, was byte-for-byte the swirl
that had been on screen. It was not a fallback rendered live. It was a
photograph of the past.

## 4. What the cache gave back

Having been forced to understand it, the cache turned out to be the best
available oracle — better than looking at the pane.

After clearing, the freshly rebuilt entries came in two sizes:

```
   3 files at 180x116
  10 files at 214x130
```

**180×116 is the `@2x` convention size.** A bundle whose `thumbnail@2x.png` was
actually read produces one. Everything else lands at 214×130. Starfield moved
from the second bucket to the first at the exact moment its thumbnail started
being honoured.

That is a scriptable check. Verifying this feature never again requires a human
to squint at a tile and judge a colour.

One claim was *not* established, and the first draft of the write-up overstated
it: 214×130 was described as "the generic fallback". All ten of those images
are **distinct**, and the swirl matched no other tile byte-for-byte across 300
distinct images in the backup, so they are not copies of one shared placeholder.
What they actually are was never determined. Nothing depends on it.

## 5. Corroboration from 289 bundles

XScreenSaver turned out to be sitting on the same machine's Homebrew cache.
Mounting its disk image:

```
$ ls -d "<mounted>/Screen Savers"/*.saver | wc -l
     289
$ # of those, carrying Contents/Resources/thumbnail.png:
     289
```

**Every one of 289 third-party legacy savers uses this convention.** Not most —
all of them. That is independent evidence the mechanism is alive and expected
to work, arrived at from a completely different direction than the magenta
test.

It also explained the cache. The pre-clear backup held **290** entries at
180×116 — 289 XScreenSaver bundles plus Apple's `Random.saver`, every one of
them a thumbnail that had been read and tiled. After the uninstall and the
clear, 3 remained. The arithmetic works out, which is a small thing, but it is
the difference between a plausible story and a checked one.

## 6. Where to generate it from

The earlier plan proposed extending `Tools/Render`, which drives a real
`NSView` through `cacheDisplay(in:to:)`.

That was rejected. It would put AppKit, an `NSView`, and potentially a window
server on the critical path for **producing the shipped bundle** — and avoiding
exactly that is why `ci.yml` is split into an engine job that needs no
frameworks and a build job that does.

So `Tools/Thumbnail` links `StarfieldEngine.swift` alone, plus CoreGraphics and
ImageIO for the encode. No AppKit, no `NSView`, no `cacheDisplay`. The rule the
project already had — *generated from the engine with a fixed seed, never
hand-drawn* — is satisfied either way, and this keeps the framework-free
property.

It also sidestepped a trap. `Render` is top-level code that writes `single.png`
and `trails.png` into its output directory **before any flag is consulted**, so
a `--thumbnail Contents/Resources` would have quietly deposited both into the
signed, shipped bundle.

## 7. 1.5517 is not a normal aspect ratio

90 ÷ 58 = 1.5517. Not 16:9, not 4:3, not 3:2.

Rendering the simulation at a display shape and scaling it into that box would
squash the stars into **rectangles** — a conspicuously poor look for a port
whose entire premise is that the original drew *squares*, because it used
`PatBlt` and nothing else.

So each size is rendered at its own dimensions, from the same seed, rather than
one being a resample of the other. Both get crisp, integer-aligned squares.

The Y flip is worth a line, because the project now has three conventions in
play. The engine measures Y downward, like Windows GDI. CoreGraphics measures it
upward, so the thumbnail flips — the same correction the AppKit view makes, and
the one the SVG output deliberately does *not* need, since SVG also measures
downward.

## 8. A single instant does not read at 90 pixels

The saver at rest is 1-pixel white dots on black. Scaled into a 90×58 box, that
is very nearly an empty rectangle. Truthful, useless.

The fix is the technique already behind the README's `trails.svg`: overlay
successive ticks without clearing the context, so stars leave radial trails. The
tile then reads as *motion outward from a vanishing point*, which is what the
screen saver actually is.

## 9. Tuning, and the photographic negative

The first attempt used density 110, warp 9, and 16 frames — reasoning that more
stars and longer trails would read better at small sizes.

It lit **55% of the frame**. The result was white with black rays: a
photographic negative of a starfield, and unmistakably wrong the moment it was
looked at.

Rather than keep guessing, the tool was made to report the fraction of lit
pixels, and the parameters swept:

```
d=110 w= 9 f=16   1x=          2x=55.15%     <- the negative
d= 55 w= 6 f= 8   1x=16.07%    2x=11.97%
d= 45 w= 5 f= 6   1x=12.43%    2x= 7.80%     <- chosen
d= 30 w= 7 f= 6   1x= 7.30%    2x= 6.05%     <- too sparse
```

Both sizes had to be measured, not just the large one. The 1x is consistently
brighter than the 2x at identical parameters, because the same picture at half
the resolution closes up the dark gaps between streaks. Tuning only on the
`@2x` produces a `@1x` that reads as mud — and the `@1x` is what a
non-Retina display shows.

The chosen settings are density 45, six frames, and **warp 5** — which is the
saver's own default, so the tile shows a new user the configuration they will
actually get. Density is above the default of 25 because 25 stars in a 90-pixel
box is close to that empty rectangle again.

§5 of the plan says legibility here is a judgement call no test settles. That
is true, and it is not an argument against measuring: the lit fraction did not
choose the winner, but it explained the disaster and narrowed the field from
guesswork to three candidates worth looking at.

## 10. The build order, which is where this gets dangerous

The code signature seals `Contents/Resources`. Confirmed directly:

```
$ codesign --verify --deep --strict build/Starfield.saver
build/Starfield.saver: valid on disk
$ echo hello > build/Starfield.saver/Contents/Resources/added-after-signing.txt
$ codesign --verify --deep --strict build/Starfield.saver
build/Starfield.saver: a sealed resource is missing or invalid
```

So generating thumbnails into a bundle that has already been signed produces a
bundle macOS refuses to load — and nothing says so until screen-blank time.

`build.sh` was reordered:

```
before:  compile saver -> Info.plist -> codesign -> compile tools -> test
after:   compile saver -> Info.plist -> generate thumbnails
         -> copy in the uninstaller -> codesign -> verify the seal -> test
```

`Tools/Thumbnail` links only the engine, so building it first costs nothing and
drags in no frameworks.

Two guards were added, because both failures are silent:

- **The seal is verified after signing**, with `--deep --strict`, so the build
  proves the signature covers what was just added instead of assuming it.
  `Sealed Resources … files=3`.
- **The dimensions are asserted before signing.** The pane finds these by
  filename and renders them at fixed sizes; a wrong dimension is invisible
  until someone opens System Settings. That check was confirmed to work by
  deliberately building a 91-pixel-wide thumbnail and watching the build abort
  before `==> signing`.

## 11. Where the files live

Nowhere in git. The images are generated at build time into `build/`, which is
gitignored, keeping the project's standing decision that no binaries are
committed.

This is a deliberate difference from the README's SVGs. Those are committed, in
a text format, precisely so CI can diff them and catch artwork drifting away
from the simulation. The thumbnails need no such check: they are regenerated on
every build from the same fixed seed, and so cannot fall out of step with the
engine in the first place. Two builds of one commit produce identical bytes —
verified by building twice and comparing hashes.

## What is still unverified

- **Whether the tile is legible at actual size on a real display.** It was
  judged from rendered PNGs at 1x and 2x, which is close but not the same as
  looking at the pane on a Retina panel from normal viewing distance.
- **What the 214×130 tiles actually are** (§4). Unimportant, but it means
  "generic fallback" should not be asserted.
- **Anything about macOS 13, 14 or 15**, the standing caveat for this whole
  project. The convention was confirmed on 26.6.2 only.

## Summary of method

The lesson is not about thumbnails. It is that a validation experiment can
return a clean, readable, completely wrong answer, and that the way to catch
that is to ask *why* the answer looks the way it does before acting on it.

The magenta test was well designed — unmistakable, impossible to misread. It
still lied, because something between the file and the screen was holding an
old copy. Understanding that intermediate layer cost an afternoon and produced
the 180×116 oracle, a documented cache behaviour, a feature
(`--refresh-preview`), and a bug fix for every existing user's upgrade.

Believing the tile would have cost the feature.
