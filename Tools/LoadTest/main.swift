import Cocoa
import ScreenSaver

// Verifies a built .saver the way macOS will: load the bundle, resolve
// NSPrincipalClass by name through the Objective-C runtime, instantiate it,
// and run a frame. This is what catches the failures that a successful
// compile does not -- a missing @objc name, an unresolved symbol, a nil init.
//
//   ./build/LoadTest build/Starfield.saver
//
// Exit status is 0 only if every stage passed, so it works as a CI gate.

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: LoadTest <path/to/X.saver>\n".utf8))
    exit(2)
}
let path = CommandLine.arguments[1]

func fail(_ message: String) -> Never {
    print("FAIL: \(message)")
    exit(1)
}

guard let bundle = Bundle(path: path) else { fail("not a bundle: \(path)") }
guard bundle.load() else { fail("bundle.load() returned false") }

// The cast is the real check: without @objc(StarfieldView) the principal class
// lookup returns nil, because Info.plist names the class as a plain string
// while Swift would have mangled it.
guard let cls = bundle.principalClass as? ScreenSaverView.Type else {
    fail("principalClass = \(String(describing: bundle.principalClass)) — not a ScreenSaverView")
}
print("OK: loaded, principalClass = \(cls)")

guard let view = cls.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                          isPreview: false) else {
    fail("init(frame:isPreview:) returned nil")
}
print("OK: instantiated \(type(of: view)), hasConfigureSheet = \(view.hasConfigureSheet)")

view.animateOneFrame()
print("OK: animateOneFrame ran")
