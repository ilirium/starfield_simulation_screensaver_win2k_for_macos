import Cocoa
import ScreenSaver

// Verification harness. Renders StarfieldView frames offscreen and also
// composites successive frames into a trail image, which should show stars
// streaking radially outward from the center.
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

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

// Additive composite: max() each frame's luminance into an accumulator.
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
guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
        bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceWhite, bytesPerRow: w, bitsPerPixel: 8),
      let dst = out.bitmapData else { exit(1) }
accum.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: w * h) }
write(out, "trails")
print("wrote single.png and trails.png (\(w)x\(h))")
