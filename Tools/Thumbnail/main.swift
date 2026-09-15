import CoreGraphics
import Foundation
import ImageIO

// Generates the preview images System Settings shows for the saver:
//
//   Contents/Resources/thumbnail.png      90 x 58
//   Contents/Resources/thumbnail@2x.png  180 x 116
//
// It is a filename convention with no Info.plist key behind it. Apple's
// Random.saver uses it, XScreenSaver ships it in 289 bundles, and it was
// confirmed still working for third-party legacy savers on macOS 26.6.2 --
// see aingineering/AING-0006-thumbnail-cache.md §1.
//
// Deliberately links StarfieldEngine alone: no AppKit, no NSView, no
// cacheDisplay, no window server. Producing the shipped bundle should not
// depend on a framework the engine does not, which is the same reason ci.yml
// keeps an engine job separate from the build job.
//
//   ./Thumbnail <out-dir>

/// One thumbnail, rendered at its target pixel size rather than scaled down
/// from a display-shaped frame.
///
/// 90x58 is an aspect ratio of 1.5517 -- neither 16:9 nor 4:3. Rendering at the
/// view's shape and resizing would squash the stars into rectangles, which is a
/// poor look for a port whose whole premise is that the original drew *squares*
/// with PatBlt.
///
/// `frames` overlays successive ticks without clearing, so the stars leave
/// radial trails. A single instant will not read at 90 pixels: the saver at
/// rest is 1px dots on black, which at this size is very nearly an empty
/// rectangle. The trails are what make it legible as motion.
func render(width: Int, height: Int, density: Int, warp: Int,
            settle: Int, frames: Int, starScale: Int, seed: UInt32) -> CGImage? {
    var engine = StarfieldEngine(seed: seed)
    engine.warpSpeed = warp
    engine.configure(width: width, height: height, density: density)
    for _ in 0..<settle { engine.step() }

    // 8-bit grayscale is the whole palette: white squares on black.
    guard let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: width,
                              space: CGColorSpaceCreateDeviceGray(),
                              bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }

    ctx.setFillColor(gray: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    // Squares, not dots, exactly as the saver draws them.
    ctx.setShouldAntialias(false)
    ctx.setFillColor(gray: 1, alpha: 1)

    for _ in 0..<frames {
        engine.step()
        for star in engine.stars {
            let p = engine.project(star)
            let side = max(1, p.size * starScale)
            // The engine measures Y downward, like Windows GDI. CoreGraphics
            // measures it upward, so flip -- the same correction the AppKit
            // view makes, and the one the SVG output does not need.
            ctx.fill(CGRect(x: p.x, y: height - p.y - side, width: side, height: side))
        }
    }
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to path: String) -> Bool {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(dest, image, nil)
    return CGImageDestinationFinalize(dest)
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// A fixed seed, for the same reason the README SVGs use one: the bundle should
// be reproducible, so two builds of the same commit produce identical bytes.
let seed: UInt32 = 0x5CEE_D300

// Tuned by looking, which §5 of the plan says is the only way to settle it, and
// checked against the fraction of lit pixels so it is not purely a matter of
// taste. The first attempt -- density 110, warp 9, 16 frames -- lit 55% of the
// frame and read as white with black rays, the photographic negative of a
// starfield. These land at roughly 12% lit at 1x and 8% at 2x.
//
// Density is above the saver's default of 25 because 25 stars in a 90px box is
// very nearly an empty rectangle. Warp is the saver's actual default, so the
// tile shows the configuration a new user gets.
let density = 45
let warp = StarfieldEngine.defaultWarp
let settle = 30
let frames = 6

// @1x and @2x are rendered independently from the same seed rather than one
// being a resample of the other, so both get crisp integer-aligned squares.
let variants = [
    (name: "thumbnail.png",    width: 90,  height: 58,  starScale: 1),
    (name: "thumbnail@2x.png", width: 180, height: 116, starScale: 2),
]

for v in variants {
    guard let image = render(width: v.width, height: v.height,
                             density: density, warp: warp,
                             settle: settle, frames: frames,
                             starScale: v.starScale, seed: seed) else {
        FileHandle.standardError.write("Thumbnail: could not render \(v.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let path = "\(outDir)/\(v.name)"
    guard writePNG(image, to: path) else {
        FileHandle.standardError.write("Thumbnail: could not write \(path)\n".data(using: .utf8)!)
        exit(1)
    }
}

print("wrote thumbnail.png (90x58) and thumbnail@2x.png (180x116)")
