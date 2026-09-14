import Cocoa
import ScreenSaver

/// Standalone harness: runs the same StarfieldView in an ordinary window so
/// the saver can be watched, screenshotted, and tuned without installing it.
/// Not part of the .saver bundle.
///
///   ./build/StarfieldPreview [density] [warpSpeed]

let args = CommandLine.arguments.dropFirst().compactMap(Int.init)
// Write to the same store the saver reads, not UserDefaults.standard.
let store = ScreenSaverDefaults(forModuleWithName: Config.bundleIdentifier) ?? .standard
store.register(defaults: [
    Config.densityKey: StarfieldEngine.defaultDensity,
    Config.warpKey: StarfieldEngine.defaultWarp,
])
if args.count > 0 { store.set(args[args.startIndex], forKey: Config.densityKey) }
if args.count > 1 { store.set(args[args.startIndex + 1], forKey: Config.warpKey) }
store.synchronize()

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let frame = NSRect(x: 0, y: 0, width: 960, height: 640)
let window = NSWindow(contentRect: frame,
                      styleMask: [.titled, .closable, .resizable],
                      backing: .buffered, defer: false)
window.title = "Starfield Simulation"
window.backgroundColor = .black

guard let saver = StarfieldView(frame: frame, isPreview: false) else {
    fatalError("could not create StarfieldView")
}
saver.autoresizingMask = [.width, .height]
window.contentView = saver
window.center()
window.makeKeyAndOrderFront(nil)
saver.startAnimation()

app.activate(ignoringOtherApps: true)
app.run()
