import Foundation

// Tests for StarfieldEngine, the pure-integer half of the port.
//
// Every assertion here is a claim about fidelity to the original binary, so
// each section names the address in docs/NOTES.md that it is checking. If one
// of these fails, the port has drifted from ssstars.scr -- read NOTES.md
// before "fixing" the engine, because the truncating division, the clamps and
// the odd placement of the speed ramp are all deliberate.
//
// This links against Sources/StarfieldEngine.swift alone: no Cocoa, no
// ScreenSaver, no NSView. That is on purpose. The engine is where arithmetic
// can actually regress, and keeping the suite framework-free means it runs on
// a headless CI runner whether or not AppKit will instantiate a view there.
//
//   ./build/EngineTests
//
// Exit status is 0 only if every check passed, so it works as a CI gate.

var checks = 0
var failures = 0

func check(_ passed: Bool, _ what: String, line: UInt = #line) {
    checks += 1
    guard !passed else { return }
    failures += 1
    print("  FAIL (line \(line)): \(what)")
}

func checkEqual<T: Equatable>(_ got: T, _ want: T, _ what: String, line: UInt = #line) {
    checks += 1
    guard got != want else { return }
    failures += 1
    print("  FAIL (line \(line)): \(what) — got \(got), want \(want)")
}

func section(_ name: String) { print("\(name)") }

// MARK: - Constants

section("constants match the disassembly")
checkEqual(StarfieldEngine.zFar, 0xA00, "zFar is 0xA00, the spawn depth and the projection scale")
checkEqual(StarfieldEngine.sizeDivisor, 0x280, "size divisor is 0x280")
checkEqual(StarfieldEngine.tickInterval, 0.050, "SetTimer interval is 50 ms, i.e. 20 fps")
checkEqual(StarfieldEngine.minDensity, 10, "density floor")
checkEqual(StarfieldEngine.maxDensity, 200, "density ceiling")
checkEqual(StarfieldEngine.defaultDensity, 25, "density default")
checkEqual(StarfieldEngine.minWarp, 0, "warp floor")
checkEqual(StarfieldEngine.maxWarp, 10, "warp ceiling")
checkEqual(StarfieldEngine.defaultWarp, 5, "warp default")

// MARK: - RNG and respawn

section("RNG and respawn (NOTES.md 0x1001c41, 0x1001c5a)")
do {
    // The Visual C++ rand() that the screen saver inlined, written out again
    // here so the engine is checked against an independent copy of the
    // sequence rather than against itself.
    var reference: UInt32 = 12_345
    func referenceRand() -> Int {
        reference = reference &* 0x343FD &+ 0x269EC3
        return Int((reference >> 16) & 0xFFFF)
    }

    let w = 800, h = 600
    var engine = StarfieldEngine(seed: 12_345)
    engine.configure(width: w, height: h, density: 12)

    checkEqual(engine.stars.count, 12, "a density of 12 produces 12 stars")

    // configure() respawns in index order and draws twice per star, X then Y.
    for (i, star) in engine.stars.enumerated() {
        checkEqual(star.x, referenceRand() % w - w / 2, "star \(i) X follows the LCG")
        checkEqual(star.y, referenceRand() % h - h / 2, "star \(i) Y follows the LCG")
        checkEqual(star.z, StarfieldEngine.zFar, "star \(i) spawns at the far plane")
    }
}

// MARK: - The speed ramp

section("the speed ramp advances per star, not per frame (NOTES.md 0x1001700)")
do {
    let w = 800, h = 600
    let warp = 5
    var engine = StarfieldEngine(seed: 99)
    engine.warpSpeed = warp
    engine.configure(width: w, height: h, density: 20)

    let target = StarfieldEngine.targetSpeed(forWarp: warp)
    checkEqual(target, 60, "warp 5 targets speed 60")

    engine.step()

    // This is the quirk the port exists to preserve. The ramp sits inside the
    // per-star loop, so on the first tick star i has already been pulled by
    // min(i + 1, target). Were the ramp hoisted to once per frame -- the
    // "obvious" cleanup -- every star would instead sit at zFar - 1.
    var survivors: [(index: Int, z: Int)] = []
    for (i, star) in engine.stars.enumerated() {
        let expected = StarfieldEngine.zFar - min(i + 1, target)
        // A star that projected off screen was recycled back to zFar in the
        // same tick, which is legitimate. Any third value is not.
        check(star.z == expected || star.z == StarfieldEngine.zFar,
              "star \(i) should be at z=\(expected) or recycled, got z=\(star.z)")
        if star.z != StarfieldEngine.zFar { survivors.append((i, star.z)) }
    }

    check(survivors.count >= 2, "at least two stars survived the first tick (saw \(survivors.count))")
    if let first = survivors.first, let last = survivors.last {
        // The discriminator between per-star and per-frame: surviving stars
        // must sit at *different* depths after a single tick.
        check(first.z > last.z,
              "later stars moved further in the same tick (star \(first.index) z=\(first.z) "
              + "> star \(last.index) z=\(last.z))")
    }
}

// MARK: - Projection

section("projection truncates toward zero (NOTES.md 0x10016a9)")
do {
    var engine = StarfieldEngine(seed: 1)
    engine.configure(width: 640, height: 480, density: 10)
    let cx = 320, cy = 240

    // Spawn depth and projection scale are the same constant, so a new star
    // lands exactly on the random screen position it was given.
    let far = StarfieldEngine.Star(x: 100, y: -50, z: StarfieldEngine.zFar)
    checkEqual(engine.project(far).x, 100 + cx, "a far-plane star projects to x + centerX")
    checkEqual(engine.project(far).y, -50 + cy, "a far-plane star projects to y + centerY")
    checkEqual(engine.project(far).size, 1, "a far-plane star is one pixel")

    // 3 * 2560 / 1000 is 7.68. The x86 idiv the original used truncates
    // toward zero, and so does Swift's / on Int -- including for negatives,
    // where the answer is -7 rather than the -8 that flooring would give.
    checkEqual(engine.project(.init(x: 3, y: 0, z: 1000)).x, 7 + cx, "positive X truncates toward zero")
    checkEqual(engine.project(.init(x: -3, y: 0, z: 1000)).x, -7 + cx, "negative X truncates toward zero")
    checkEqual(engine.project(.init(x: 0, y: 3, z: 1000)).y, 7 + cy, "positive Y truncates toward zero")
    checkEqual(engine.project(.init(x: 0, y: -3, z: 1000)).y, -7 + cy, "negative Y truncates toward zero")

    // Motion is radially outward from the center: the same star projects
    // further from center as it approaches the eye.
    let near = StarfieldEngine.Star(x: 100, y: 0, z: 640)
    check(engine.project(near).x > engine.project(far).x, "a nearer star projects further out")
}

// MARK: - Star size

section("star size ramps as (2560 - z) / 640 + 1 (NOTES.md 0x10016e3)")
do {
    var engine = StarfieldEngine(seed: 1)
    engine.configure(width: 640, height: 480, density: 10)
    func size(atZ z: Int) -> Int { engine.project(.init(x: 0, y: 0, z: z)).size }

    checkEqual(size(atZ: 2560), 1, "z=2560 is one pixel")
    checkEqual(size(atZ: 1921), 1, "z=1921 is still one pixel, just above the step")
    checkEqual(size(atZ: 1920), 2, "z=1920 is the first step up")
    checkEqual(size(atZ: 1280), 3, "z=1280 is three pixels")
    checkEqual(size(atZ: 640), 4, "z=640 is four pixels")
    checkEqual(size(atZ: 1), 4, "z=1 is four pixels")

    // The formula's ceiling is 5, but reaching it needs z == 0 -- and
    // project() cannot be called at z == 0 at all, because the perspective
    // divide traps before the size term is ever reached. That is exactly why
    // step() respawns a star at zero rather than clamping it to 1: the
    // respawn is load-bearing, not cosmetic. So size 5 is unreachable and the
    // drawn range is 1...4, where NOTES.md gives the formula's range rather
    // than the reachable one. Asserted arithmetically, since calling
    // project(atZ: 0) here would crash the suite.
    checkEqual((StarfieldEngine.zFar - 0) / StarfieldEngine.sizeDivisor + 1, 5,
               "the size formula's ceiling is 5, at a depth nothing survives to be drawn at")

    var outOfRange: [Int] = []
    for z in 1...StarfieldEngine.zFar where !(1...4).contains(size(atZ: z)) {
        outOfRange.append(z)
    }
    checkEqual(outOfRange.count, 0, "every reachable depth gives a size in 1...4")
}

// MARK: - Clamps

section("density and warp clamps (NOTES.md 0x1001d52)")
do {
    var engine = StarfieldEngine(seed: 7)
    engine.configure(width: 640, height: 480, density: 3)
    checkEqual(engine.stars.count, StarfieldEngine.minDensity, "a density below the floor clamps up to 10")
    engine.configure(width: 640, height: 480, density: 5_000)
    checkEqual(engine.stars.count, StarfieldEngine.maxDensity, "a density above the ceiling clamps to 200")
    engine.configure(width: 640, height: 480, density: 25)
    checkEqual(engine.stars.count, 25, "a density in range is used as given")

    checkEqual(StarfieldEngine.targetSpeed(forWarp: 0), 10, "warp 0 targets 10")
    checkEqual(StarfieldEngine.targetSpeed(forWarp: 10), 110, "warp 10 targets 110")
    checkEqual(StarfieldEngine.targetSpeed(forWarp: StarfieldEngine.defaultWarp), 60, "the default warp targets 60")
}

// MARK: - Long-run invariants

section("invariants hold over a long run")
do {
    let w = 1_024, h = 768
    var engine = StarfieldEngine(seed: 2_026)
    engine.warpSpeed = StarfieldEngine.maxWarp   // fastest ramp, most recycling
    engine.configure(width: w, height: h, density: StarfieldEngine.maxDensity)

    var badDepth = 0, offScreen = 0, recycled = 0, stalled = 0
    var previous = engine.stars.map { ($0.x, $0.y, $0.z) }

    for _ in 0..<600 {
        engine.step()
        for (i, star) in engine.stars.enumerated() {
            // z == 0 would divide by zero on the next projection, which is why
            // the engine respawns there instead of clamping to 1.
            if star.z < 1 || star.z > StarfieldEngine.zFar { badDepth += 1 }
            let p = engine.project(star)
            if p.x < 0 || p.y < 0 || p.x > w || p.y > h { offScreen += 1 }
            if star.z > previous[i].2 { recycled += 1 }   // only a respawn raises z

            // A star must move every tick unless it was recycled, and a
            // recycle always sets z back to zFar exactly. So an unchanged
            // state at any depth short of zFar means the star is stuck. The
            // zFar exclusion matters: two respawns in a row can land on the
            // same random position by chance, which is not a stall.
            if star.z < StarfieldEngine.zFar && (star.x, star.y, star.z) == previous[i] {
                stalled += 1
            }
        }
        previous = engine.stars.map { ($0.x, $0.y, $0.z) }
    }

    checkEqual(badDepth, 0, "z stays within 1...zFar — never zero, never negative")
    checkEqual(offScreen, 0, "every star projects inside the frame after a tick")
    checkEqual(stalled, 0, "no star is ever stuck — each tick it either moves or is recycled")
    check(recycled > 500, "stars recycle steadily over a long run (saw \(recycled))")
}

// MARK: - The center ray

section("a star on the exact center ray is recycled, not pinned")
do {
    // x == 0 and y == 0 together put a star on the ray through the eye, where
    // the projection stays at the screen center however small z becomes. That
    // star is the single case distinguishing "respawn at z == 0" from the
    // tempting "clamp z to 1": every other star at z == 1 projects far off
    // screen and is recycled a line later anyway, but this one stays in frame
    // and, if clamped, sits pinned at the center of the screen forever.
    //
    // A small frame is what makes the case observable. At 8x8 roughly one
    // respawn in 64 lands on the center ray; at 1024x768 it is one in 786,432,
    // so a full-size run never reaches the branch at all.
    let w = 8, h = 8
    var engine = StarfieldEngine(seed: 31_337)
    engine.warpSpeed = StarfieldEngine.maxWarp
    engine.configure(width: w, height: h, density: StarfieldEngine.maxDensity)

    var sightings = 0, pinned = 0
    var previous = engine.stars.map { ($0.x, $0.y, $0.z) }
    for _ in 0..<2_000 {
        engine.step()
        for (i, star) in engine.stars.enumerated() {
            if star.x == 0 && star.y == 0 { sightings += 1 }
            if star.z < StarfieldEngine.zFar && (star.x, star.y, star.z) == previous[i] {
                pinned += 1
            }
        }
        previous = engine.stars.map { ($0.x, $0.y, $0.z) }
    }

    check(sightings > 0, "the center-ray case actually occurred (saw \(sightings) sightings)")
    checkEqual(pinned, 0, "a center-ray star is recycled rather than pinned at the center")
}

// MARK: - Determinism

section("a fixed seed is reproducible (what the SVG drift check rests on)")
do {
    func field(seed: UInt32) -> [Int] {
        var engine = StarfieldEngine(seed: seed)
        engine.warpSpeed = 5
        engine.configure(width: 800, height: 600, density: 50)
        for _ in 0..<200 { engine.step() }
        return engine.stars.flatMap { [$0.x, $0.y, $0.z] }
    }
    checkEqual(field(seed: 4_242), field(seed: 4_242), "the same seed gives the same field after 200 ticks")
    check(field(seed: 4_242) != field(seed: 4_243), "different seeds diverge")
}

// MARK: - Reconfiguration

section("reconfiguration")
do {
    var engine = StarfieldEngine(seed: 5)
    engine.configure(width: 800, height: 600, density: 30)
    for _ in 0..<50 { engine.step() }
    check(engine.stars.contains { $0.z != StarfieldEngine.zFar }, "the field has left the far plane")

    engine.configure(width: 1_200, height: 900, density: 30)
    check(engine.stars.allSatisfy { $0.z == StarfieldEngine.zFar }, "a resize puts every star back at the far plane")
    checkEqual(engine.stars.count, 30, "the density survives a resize")

    // A zero-size frame is what a view reports before it has been laid out.
    var blank = StarfieldEngine(seed: 5)
    blank.configure(width: 0, height: 0, density: 30)
    let before = blank.stars.map(\.z)
    blank.step()
    checkEqual(blank.stars.map(\.z), before, "step() is a no-op on a zero-size frame")
}

// MARK: - Result

print("")
if failures == 0 {
    print("OK: \(checks) checks passed")
    exit(0)
} else {
    print("FAILED: \(failures) of \(checks) checks")
    exit(1)
}
