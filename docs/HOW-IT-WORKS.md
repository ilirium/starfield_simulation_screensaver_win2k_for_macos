# How the macOS port works

Written for someone who knows how to program but has never touched Swift,
AppKit, or Objective-C.

It explains the port by comparing it to the Win32 original, because the two
are mostly one-to-one — Apple just uses different words for the same ideas.
**If you do not know Win32 either, read `WIN32-PRIMER.md` first**; it builds
that half from nothing and assumes no Windows background. Without it the
comparisons here are explaining one unfamiliar thing in terms of another.

`NOTES.md` has the recovered constants. `TEARDOWN.md` has the disassembly
story. This file is about the thing that was built.

---

## 1. A macOS screen saver is a plugin, not a program

On Windows, `ssstars.scr` **is an executable**. It has an entry point and a
`WinMain`, and the system runs it with a flag telling it what to do:

| Flag | Meaning |
|---|---|
| `/s` | run full screen |
| `/c` | show the settings dialog |
| `/p <hwnd>` | draw the little preview |

The program owns its process, creates its own window, pumps its own message
loop, and calls `SetTimer` to drive animation.

macOS inverts all of that. A screen saver is **a plugin loaded into somebody
else's process**. You do not get a `main()`. You do not create a window. You
do not own the timer or the event loop. The system owns all of it, and it
loads your code and asks it to fill in a rectangle.

The unit of distribution is a **bundle** — which on macOS is just a directory
with a fixed layout and a package extension. `Starfield.saver` looks like a
single file in Finder, but it is this:

```
Starfield.saver/
  Contents/
    Info.plist              <- manifest: who am I, what class do you load
    MacOS/
      Starfield             <- the compiled code (a Mach-O "bundle")
    _CodeSignature/
      CodeResources         <- signature, added by codesign
```

`Info.plist` is an XML manifest, roughly the moral equivalent of a Windows
resource block plus a registry entry. The line that matters most:

```xml
<key>NSPrincipalClass</key>
<string>StarfieldView</string>
```

That is the whole contract. The system loads the binary, looks up a class by
**that exact name**, instantiates it, and starts talking to it. Everything
else in this project exists to make that one class behave.

The compiled file is a Mach-O of type `MH_BUNDLE` — a loadable module, closer
to a DLL than to an EXE, except it is specifically the "load me at runtime by
name" flavor rather than the "link against me" flavor.

---

## 2. The libraries involved

Apple's stack is layered. Three layers matter here.

**ScreenSaver.framework** — the small, specific one. A "framework" is just
Apple's word for a shared library bundled with its headers. It gives you two
classes:

- `ScreenSaverView` — the base class you subclass. This is your saver.
- `ScreenSaverDefaults` — where your settings live.

**AppKit** (part of the umbrella called Cocoa) — the general macOS GUI toolkit,
the rough counterpart to USER32 plus the common controls. Windows, views,
buttons, sliders, event handling. Class names start with `NS` for historical
reasons (NeXTSTEP, the 1980s OS that macOS descends from).

**Core Graphics**, also called Quartz 2D — the 2D drawing engine, the rough
counterpart to GDI32. Its names start with `CG`. This is what actually puts
pixels down.

The inheritance chain is worth knowing, because it explains why the class can
do things this project never wrote code for:

```
NSObject                 root of everything in Cocoa
  └── NSResponder        can receive events
      └── NSView         occupies a rectangle, knows how to draw itself
          └── ScreenSaverView    + animation timer, + config sheet hooks
              └── StarfieldView  <- ours
```

`NSView` is the counterpart of an HWND-with-a-WndProc. `ScreenSaverView` adds
a timer and a few conventions on top. We add stars.

Similarly:

```
NSUserDefaults           per-app preferences store (like the registry)
  └── ScreenSaverDefaults    same thing, namespaced per saver module
```

Both of those parent-class facts are checkable in the SDK headers; they are
not folklore.

---

## 3. Enough Swift to read the code

Swift is Apple's current language — statically typed, compiled, memory-managed
by reference counting rather than a garbage collector. The handful of
constructs this project uses:

**`let` is const, `var` is mutable.**

```swift
let zFar = 2560     // constant
var speed = 0       // variable
```

**Types are inferred but static.** `var speed = 0` makes an `Int`. There is no
implicit numeric conversion at all — an `Int` will not silently become a
`CGFloat`, which is why the drawing code is full of explicit `CGFloat(...)`
conversions. Verbose, but it means a truncation can never happen by accident.

**`struct` is a value type, `class` is a reference type.** A `struct` is copied
on assignment, like a C struct. A `class` is a pointer with automatic
reference counting, like a C++ `shared_ptr`. This distinction drives the whole
file layout, as the next section explains.

**A method that modifies a `struct` must say `mutating`.** The compiler tracks
it.

```swift
mutating func step() { ... }
```

**Optionals.** A type ending in `?` may hold a value or `nil`, and the
compiler will not let you use it without handling the `nil` case. `Int` can
never be null; `Int?` can. `guard let x = maybeX else { return }` means
"unwrap it or bail out". This is the same idea as a nullable pointer, except
it is enforced.

**Computed properties** look like fields but run code:

```swift
private var starScale: CGFloat { max(1.0, bounds.width / 640.0) }
```

No storage; recomputed on every read.

**`override`** is mandatory when replacing an inherited method, so a typo
becomes a compile error instead of a method that silently never runs.

**`&*` and `&+` are wrapping arithmetic.** Plain `*` and `+` **trap on
overflow** in Swift — the program halts rather than silently wrapping. The
random number generator needs the classic C wraparound, so it asks for it
explicitly:

```swift
seed = seed &* 0x343FD &+ 0x269EC3
```

That is a deliberate, visible choice, not an accident of the type.

**`@objc(StarfieldView)`** deserves its own note. Swift normally *mangles*
class names in the Objective-C runtime, encoding the module name and the
lengths of each part. But `Info.plist` has to name the class as a plain
string, and the loader looks it up by that string. `@objc(StarfieldView)` pins
the runtime name so the lookup succeeds. Without it the saver compiles, loads,
and then fails to start with an unhelpful message.

You can see both outcomes in the built binary. `StarfieldView` carries the
attribute; `ConfigController` does not, because nothing looks it up by name:

```
$ strings -a build/Starfield.saver/Contents/MacOS/Starfield | grep -i 'StarfieldView\|_TtC'
StarfieldView
StarfieldView
_TtC9Starfield16ConfigController
```

`_TtC` marks a Swift class, `9Starfield` is the module name with its length,
and `16ConfigController` is the class name with its length. That is what
`NSPrincipalClass` would have to contain without the attribute.

Objective-C is still under everything here. Swift talks to Cocoa through it,
which is also why the settings-sheet callbacks are marked `@objc` — they are
invoked by name through the Objective-C message dispatcher, not called
directly.

---

## 4. The shape of the code

Four files, deliberately split:

| File | Type | Job |
|---|---|---|
| `StarfieldEngine.swift` | `struct` | The simulation. No UI, no drawing. |
| `StarfieldView.swift` | `class` | The plugin. Talks to macOS, draws. |
| `ConfigController.swift` | `class` | The settings dialog. |
| `main.swift` | — | Standalone test harness, *not* in the saver. |

The engine is a `struct` holding plain `Int` arrays and containing zero
Apple-specific types. That is on purpose. It means the physics can be
instantiated and stepped from anywhere — a test, a command-line tool, an
offscreen renderer — without a window, a screen, or a running app. All the
verification described in `TEARDOWN.md` §10 depends on that separation.

The view is a `class` because Cocoa requires it: the system holds a reference
to your object, calls back into it, and expects reference semantics.

---

## 5. The engine: what actually moves

Each star is three integers.

```swift
struct Star { var x = 0, y = 0, z = StarfieldEngine.zFar }
```

`x` and `y` are **not** screen coordinates. They are offsets from the center
of the screen, in a space where the star sits at depth `z`. `z` runs from 2560
(far away) down toward 0 (at your eye).

### Projection

The screen position comes from a perspective divide — the same idea as
dividing by `w` in 3D graphics, minus the matrices:

```swift
func project(_ star: Star) -> (x: Int, y: Int, size: Int) {
    (x: star.x * Self.zFar / star.z + centerX,
     y: star.y * Self.zFar / star.z + centerY,
     size: (Self.zFar - star.z) / Self.sizeDivisor + 1)
}
```

Large `z` (far) shrinks the offset toward the center. As `z` falls, the same
`x` and `y` push the star further out — so stars stream outward from the
middle, faster the closer they get. That is the entire visual effect.

Note this is **integer division**, which truncates. That is not sloppiness; it
is what the original did, and reproducing it preserves the slightly steppy
motion near the center. Swift's `/` on `Int` truncates exactly like C's.

### Spawning

```swift
stars[i].x = rand16() % width  - centerX
stars[i].y = rand16() % height - centerY
stars[i].z = Self.zFar
```

The clever bit inherited from the original: the spawn depth `zFar` is the
*same number* as the projection scale. At `z == 2560` the divide is the
identity, so a new star appears exactly at its random screen position, then
moves outward from there. Uniform coverage with no trigonometry and no square
roots — which is how this ran on 2003 hardware.

### The tick

```swift
mutating func step() {
    for i in stars.indices {
        if speed < target { speed += 1 } else if speed > target { speed -= 1 }

        stars[i].z -= speed
        if stars[i].z < 0 { stars[i].z = 0 }
        if stars[i].z == 0 { respawn(i) }

        let p = project(stars[i])
        if p.x < 0 || p.y < 0 || p.x > width || p.y > height { respawn(i) }
    }
}
```

Three things to notice.

**The speed easing is inside the loop**, so it advances once per *star*, not
once per frame. That is faithful to the original — acceleration therefore
depends on the star count, which is odd but real.

**`z == 0` forces a respawn** rather than clamping to 1, because the very next
thing that happens is a division by `z`. The original did exactly this, and
the reason is the same: dividing by zero.

**Stars are recycled when they leave the screen**, so the count stays fixed.
Nothing is ever allocated after setup.

### Randomness

```swift
private mutating func rand16() -> Int {
    seed = seed &* 0x343FD &+ 0x269EC3
    return Int((seed >> 16) & 0xFFFF)
}
```

A linear congruential generator — specifically the Visual C++ runtime's
`rand()`, which the original had inlined into it. Statistically mediocre and
completely adequate for throwing stars at a screen. Reproduced for
authenticity. The one change: it is seeded from the system RNG rather than the
CRT's fixed `1`, so two launches do not draw the same sky.

---

## 6. The view: how macOS drives it

`ScreenSaverView` gives you a small set of hooks. The saver is these four
overrides and nothing more.

### Setup

```swift
override init?(frame: NSRect, isPreview: Bool)
```

The system constructs the view, handing it a rectangle and a flag. `isPreview`
is true for the small thumbnail in System Settings, so a heavier saver could
cut detail there. This one ignores it — the work is trivial either way.

The `?` makes it a *failable* initializer: it is allowed to return `nil`.

### The animation clock

```swift
animationTimeInterval = StarfieldEngine.tickInterval   // 0.050
```

Set this property and the base class runs a timer for you. No `SetTimer`, no
message loop, no `WM_TIMER`. On each tick it calls:

```swift
override func animateOneFrame() {
    engine.step()
    setNeedsDisplay(bounds)
}
```

`setNeedsDisplay` does **not** draw. It marks the view dirty — the exact
counterpart of `InvalidateRect`. The system coalesces invalidations and calls
the drawing method later, when it is ready to composite a frame.

0.050 s is 20 fps, matching the original's `SetTimer(hwnd, 1, 50, NULL)`.

### Drawing

```swift
override func draw(_ rect: NSRect) {
```

This is `WM_PAINT`. You never call it; the system does. (In Objective-C it is
spelled `drawRect:`, which is the name you will see in every older tutorial —
same method.)

```swift
guard let ctx = NSGraphicsContext.current?.cgContext else { return }
```

`NSGraphicsContext.current` is the destination set up for you before `draw` is
called — the analogue of the `HDC` you get from `BeginPaint`. `.cgContext`
drops from AppKit down to the Core Graphics layer, where the real drawing
calls live.

```swift
ctx.setFillColor(NSColor.black.cgColor)
ctx.fill(bounds)

ctx.setShouldAntialias(false)
ctx.setFillColor(NSColor.white.cgColor)
```

`setShouldAntialias(false)` is a fidelity decision, not an optimization. The
original drew with `PatBlt`, which fills rectangles with hard edges. Modern 2D
engines antialias by default, which would give soft grey-edged stars — subtly
wrong. Turning it off restores the crunchy look.

Then every star is projected into a rectangle:

```swift
for star in engine.stars {
    let p = engine.project(star)
    let side = max(1.0, CGFloat(p.size) * scale).rounded()
    squares.append(CGRect(x: CGFloat(p.x), y: height - CGFloat(p.y) - side,
                          width: side, height: side))
}
ctx.fill(squares)
```

**One call fills all of them.** `CGContext.fill` takes an array, so 200 stars
cost one call into the graphics engine rather than 200.

### The coordinate flip

`height - p.y - side` is doing real work.

Windows GDI puts the origin at the **top-left** with **y increasing downward**.
AppKit's default for a view is the origin at the **bottom-left** with **y
increasing upward** — the mathematical convention, not the screen one. The
engine thinks in Windows coordinates because it is a faithful port, so y is
flipped at the moment of drawing. Subtracting `side` as well accounts for a
rectangle being anchored at its lower-left corner here versus its upper-left
corner there.

Get this wrong and the starfield still looks plausible — which is exactly why
it is worth calling out. A vertically mirrored radial explosion is very hard
to spot by eye.

### The Retina problem

```swift
private var starScale: CGFloat { max(1.0, bounds.width / 640.0) }
```

This is the one place the port deliberately disobeys the original.

Sizes of 1–5 were tuned for a 640-pixel-wide CRT, where a 5-pixel star covered
a noticeable fraction of the screen. macOS measures views in **points**, not
pixels, and handles Retina scaling underneath, so drawing "5" on a modern
display gives a physically sensible dot — but on a 1512-point-wide screen it
is proportionally about 2.4× finer than what the original looked like.

Scaling by `width / 640` restores the *apparent* proportions. Set it to `1.0`
for pixel-exact output. It is recorded in `NOTES.md` as one of three
deliberate deviations.

---

## 7. Settings

```swift
ScreenSaverDefaults(forModuleWithName: "com.ilirium.Starfield")
```

`ScreenSaverDefaults` is a namespaced preferences store — key/value pairs
persisted to a plist file, the rough counterpart of a registry key. The
original read `Density` and `WarpSpeed` from `control.ini`; the port keeps
**the same two key names**.

```swift
defaults?.register(defaults: [
    Config.densityKey: StarfieldEngine.defaultDensity,   // 25
    Config.warpKey: StarfieldEngine.defaultWarp,         // 5
])
```

`register(defaults:)` supplies fallbacks without writing anything to disk — a
first launch reads 25 and 5 without creating a file.

There is one small piece of design worth pointing out:

```swift
protocol ScreenSaverDefaultsStore: AnyObject {
    func integer(forKey key: String) -> Int
    func set(_ value: Int, forKey key: String)
    func synchronize() -> Bool
}

extension UserDefaults: ScreenSaverDefaultsStore {}
```

A `protocol` is an interface. The settings dialog is written against this
three-method interface instead of against `ScreenSaverDefaults` directly, so
the standalone test harness can hand it a plain `UserDefaults`. The
`extension` line retroactively declares that Apple's existing class already
satisfies the interface — no subclassing, no wrapper, no changes to Apple's
code. Swift lets you add conformance to a type you did not write.

---

## 8. The settings dialog

The original's "Starfield Simulation Setup" had a spin control for density and
a scroll bar for warp speed. The port rebuilds it:

```swift
override var hasConfigureSheet: Bool { true }
override var configureSheet: NSWindow? { ... }
```

Answer `true` and System Settings offers an options button; return a window
and it gets presented as a *sheet* — the panel that slides down attached to
the parent window, rather than a free-floating dialog.

The dialog is built in code, no visual designer file:

```swift
let densityRow = NSStackView(views: [density, densityField, densityStepper])
let stack = NSStackView(views: [densityRow, warpRow, buttons])
stack.orientation = .vertical
```

`NSStackView` is a layout container — it arranges children in a row or column
and handles spacing. Under it is **Auto Layout**, a constraint solver: instead
of computing pixel positions the way a Win32 dialog template does, you declare
relationships and the system solves them.

```swift
warpRow.widthAnchor.constraint(equalTo: densityRow.widthAnchor)
```

"These two rows are the same width." The solver works out the numbers, and the
layout survives font changes and localization.

Controls are wired with **target/action**, Cocoa's callback mechanism:

```swift
densityStepper.target = self
densityStepper.action = #selector(densityChanged)
```

A `#selector` is a method *name*, looked up and dispatched through the
Objective-C runtime — which is why the receiving methods must be marked
`@objc`. It is the same idea as a `WM_COMMAND` handler, with the switch
statement replaced by a name lookup.

One non-obvious line in the view:

```swift
configController = controller   // the sheet is not retained for us
```

Swift manages memory by reference counting. `configureSheet` returns the
*window*, and nothing in the system holds onto the controller object that owns
it. Without storing it, the controller's reference count would hit zero the
moment the function returned, it would be deallocated, and the dialog's
buttons would be wired to a dead object. Keeping the reference in a property
keeps it alive.

---

## 9. Building it without Xcode

There is no Xcode project and no package manifest. `build.sh` calls the
compiler directly, and only the Command Line Tools are needed.

The awkward part is that a `.saver` must be a Mach-O **bundle**
(`MH_BUNDLE`), and `swiftc` will not emit one — it produces executables and
dynamic libraries. So the build goes in two steps:

```sh
swiftc -O -wmo -emit-object -o Starfield.o <sources>

clang -bundle -o Starfield.saver/Contents/MacOS/Starfield Starfield.o \
      -framework ScreenSaver -framework Cocoa \
      -Xlinker -rpath -Xlinker /usr/lib/swift
```

`-wmo` is **whole module optimization**: compile all the source files together
as one unit. It is required here for a practical reason — without it `swiftc`
emits one object file per source file and refuses the single `-o`
("cannot specify -o when generating multiple output files"). As a bonus it
lets the optimizer inline across file boundaries.

`-rpath /usr/lib/swift` tells the loader where the Swift runtime lives. Since
Swift 5 the runtime ships **with macOS** rather than inside each app, so
nothing needs to be bundled.

Finally:

```sh
codesign --force --deep --sign - Starfield.saver
```

`--sign -` is an *ad-hoc* signature: the code is sealed against tampering but
not tied to a developer identity. Modern macOS will not load an unsigned
bundle. A saver meant for distribution to other people would need a real
Developer ID and notarization; for personal use, ad-hoc is enough.

---

## 10. Running and checking it

Two harnesses exist, and neither ships inside the `.saver`.

**`Sources/main.swift`** builds `StarfieldPreview`, an ordinary app that puts
the very same `StarfieldView` in a normal resizable window:

```sh
./build/StarfieldPreview 120 8      # density, warpSpeed
```

Iterating this way takes seconds. Installing a saver and waiting for the
screen to blank does not.

**`Tools/main.swift`** builds the offscreen renderer. It never opens a window:

```swift
let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
view.cacheDisplay(in: view.bounds, to: rep)
```

`cacheDisplay` runs the real `draw(_:)` into an in-memory bitmap. That gives
frames as PNGs with no window, no display, and — importantly — no screen
recording of anyone's actual desktop. It also produces the max-composite trail
image that serves as the regression check: if the perspective divide were
wrong, the streaks would not converge on the center.

Both harnesses link the same three source files the saver does, so they
exercise the real code rather than a copy.

---

## 11. What happens when the screen blanks

You install it by copying the bundle:

```sh
cp -R build/Starfield.saver ~/Library/"Screen Savers"/
```

Then, on macOS 14 and later, the sequence is:

1. The system decides the screen should blank.
2. It launches a host process named **`legacyScreenSaver`**. Third-party
   savers are no longer loaded into a system process directly — they run
   sandboxed and isolated, so a crashing saver takes down only that host.
3. The host reads `Info.plist`, finds `NSPrincipalClass`, loads the Mach-O,
   and looks up the class `StarfieldView` in the Objective-C runtime — which
   resolves only because of the `@objc(StarfieldView)` attribute from §3.
4. It instantiates the view at screen size and calls `startAnimation()`.
5. Every 50 ms: `animateOneFrame()` → `engine.step()` → `setNeedsDisplay`.
6. Whenever the system composites: `draw(_:)` → ~200 rectangles → one
   `ctx.fill(squares)` call.
7. A key press or mouse move → `stopAnimation()` and the host exits.

A practical consequence of step 2: if something goes wrong, the crash reports
name `legacyScreenSaver`, not `Starfield`. That is the process to look for.

### More than one display

Step 4 says "instantiates the view at screen size", and with several monitors
that happens **once per screen** — each display gets its own `StarfieldView`,
its own engine, and therefore its own center point to fly out of.

The original behaves differently. It asks Windows for the *virtual screen* —
the bounding box of every monitor combined — and creates a single window
across all of them, so the stars stream out of one point somewhere in the
middle of the whole arrangement (`TEARDOWN.md` §11).

Neither is a choice the code makes. On Windows the program measures the
desktop itself; on macOS the host decides how many views exist and hands each
one a rectangle. The port could not span displays without abandoning the
`ScreenSaverView` contract entirely.

---

## 12. Windows to macOS, side by side

| Original (Win32) | Port (macOS) |
|---|---|
| `ssstars.scr`, an EXE | `Starfield.saver`, a loadable bundle |
| `WinMain` + `/s` `/c` `/p` flags | no entry point; system loads a class |
| `RegisterClassW` / `CreateWindowExW` | none — the host owns the window |
| `WndProc` + message loop | override methods on `ScreenSaverView` |
| `SetTimer` + `WM_TIMER` | `animationTimeInterval` + `animateOneFrame()` |
| `WM_PAINT` / `BeginPaint` | `draw(_:)` |
| `InvalidateRect` | `setNeedsDisplay(_:)` |
| `HDC` | `NSGraphicsContext.current.cgContext` |
| `PatBlt(..., WHITENESS)` | `ctx.fill([CGRect])` |
| `GetStockObject(WHITE_BRUSH)` | `ctx.setFillColor(...)` |
| origin top-left, y down | origin bottom-left, y up |
| `control.ini` via `GetPrivateProfileIntW` | `ScreenSaverDefaults` plist |
| dialog template in `.rsrc` | `NSStackView` + Auto Layout in code |
| `WM_COMMAND` switch | target/action + `#selector` |
| `fmsctls_updown32` spinner | `NSStepper` |
| scroll bar for warp | `NSSlider` |
| CRT `rand()` | the same LCG, reimplemented |

The physics is identical down to the truncating divides. Everything else is
the same idea wearing different names — with one genuine reversal, the y axis,
and one deliberate concession to modern displays, the star scale.
