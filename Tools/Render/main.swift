import Cocoa
import ScreenSaver

// Verification and illustration harness.
//
//   PNG: renders real StarfieldView frames offscreen via cacheDisplay, plus a
//        max-composite trail image. The trail image is the regression check --
//        stars must streak radially outward and grow along the way.
//   SVG: the same simulation emitted as vector art for the README. Generated
//        from StarfieldEngine rather than hand-drawn, so the picture cannot
//        drift away from the code.
//
//   ./render <out-dir> [--svg <repo-dir>]

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : "."
let svgDir = args.firstIndex(of: "--svg").map { args[$0 + 1] }

// MARK: - PNG: drive the real view offscreen

let store = ScreenSaverDefaults(forModuleWithName: Config.bundleIdentifier) ?? .standard
store.set(120, forKey: Config.densityKey)
store.set(5, forKey: Config.warpKey)
store.synchronize()

let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
guard let view = StarfieldView(frame: frame, isPreview: false) else { exit(1) }

func snapshot() -> NSBitmapImageRep? {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    }
}

for _ in 0..<40 { view.animateOneFrame() }
guard let single = snapshot() else { exit(1) }
write(single, "single")

let w = single.pixelsWide, h = single.pixelsHigh
var accum = [UInt8](repeating: 0, count: w * h)
for _ in 0..<26 {
    view.animateOneFrame()
    guard let rep = snapshot(), let src = rep.bitmapData else { continue }
    let spp = rep.samplesPerPixel, rb = rep.bytesPerRow
    for y in 0..<h {
        for x in 0..<w {
            let v = src[y * rb + x * spp]
            if v > accum[y * w + x] { accum[y * w + x] = v }
        }
    }
}
if let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceWhite, bytesPerRow: w, bitsPerPixel: 8),
   let dst = out.bitmapData {
    accum.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: w * h) }
    write(out, "trails")
}
print("wrote single.png and trails.png (\(w)x\(h))")

// MARK: - SVG: the same simulation as vector art

/// Renders `frames` ticks of the engine into one SVG. With `frames == 1` this
/// is what the saver looks like; with more, every frame is overlaid so the
/// stars leave the radial trails that prove the perspective divide is right.
///
/// No Y flip here: SVG measures Y downward, exactly like Windows GDI, so the
/// engine's own coordinates go straight through. The macOS view is the odd one
/// out (see HOW-IT-WORKS.md, "The coordinate flip").
func makeSVG(width: Int, height: Int, density: Int, warp: Int,
             settle: Int, frames: Int, scale: Double, seed: UInt32) -> String {
    var engine = StarfieldEngine(seed: seed)
    engine.warpSpeed = warp
    engine.configure(width: width, height: height, density: density)
    for _ in 0..<settle { engine.step() }

    var rects = ""
    var drawn = 0
    for _ in 0..<frames {
        engine.step()
        for star in engine.stars {
            let p = engine.project(star)
            let side = max(1, Int((Double(p.size) * scale).rounded()))
            // Trim stars straddling the edge so the art has clean margins.
            guard p.x >= 0, p.y >= 0, p.x + side <= width, p.y + side <= height else { continue }
            rects += #"<rect x="\#(p.x)" y="\#(p.y)" width="\#(side)" height="\#(side)"/>"#
            drawn += 1
        }
        rects += "\n"
    }

    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(width) \(height)" \
    width="\(width)" height="\(height)" role="img" \
    aria-label="Starfield Simulation, \(frames) frame\(frames == 1 ? "" : "s")">
    <rect width="\(width)" height="\(height)" fill="#000"/>
    <g fill="#fff" shape-rendering="crispEdges">
    \(rects)</g>
    </svg>

    """
}

if let svgDir {
    // Fixed seeds: the committed SVGs must regenerate byte-for-byte, so CI can
    // diff them and catch artwork silently drifting from the simulation.
    let still = makeSVG(width: 640, height: 400, density: 140, warp: 5,
                        settle: 40, frames: 1, scale: 1.6, seed: 0x5CEE_D100)
    let trails = makeSVG(width: 640, height: 400, density: 70, warp: 7,
                         settle: 30, frames: 22, scale: 1.4, seed: 0x5CEE_D200)
    try? still.write(toFile: "\(svgDir)/starfield.svg", atomically: true, encoding: .utf8)
    try? trails.write(toFile: "\(svgDir)/trails.svg", atomically: true, encoding: .utf8)
    print("wrote starfield.svg (\(still.utf8.count) B) and trails.svg (\(trails.utf8.count) B)")
}
