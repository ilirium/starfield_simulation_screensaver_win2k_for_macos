import ScreenSaver

/// The screen saver view. Draws what ssstars.scr drew with PatBlt: white
/// axis-aligned squares on black, no antialiasing, no trails.
@objc(StarfieldView)
final class StarfieldView: ScreenSaverView {

    private var engine = StarfieldEngine()
    private var defaults: ScreenSaverDefaults?
    private var configController: ConfigController?

    /// The original sized stars 1...5 px on a 640 px wide CRT. Reproducing
    /// that literally on a 1512 pt display leaves them noticeably finer than
    /// the screen saver people remember, so sizes scale with width. Set this
    /// to 1.0 for pixel-exact output.
    private var starScale: CGFloat { max(1.0, bounds.width / 640.0) }

    // MARK: Lifecycle

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        animationTimeInterval = StarfieldEngine.tickInterval
        defaults = ScreenSaverDefaults(forModuleWithName: Config.bundleIdentifier)
        defaults?.register(defaults: [
            Config.densityKey: StarfieldEngine.defaultDensity,
            Config.warpKey: StarfieldEngine.defaultWarp,
        ])
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        reloadSettings()
    }

    private func reloadSettings() {
        let density = defaults?.integer(forKey: Config.densityKey) ?? StarfieldEngine.defaultDensity
        let warp = defaults?.integer(forKey: Config.warpKey) ?? StarfieldEngine.defaultWarp
        engine.warpSpeed = warp
        engine.configure(width: Int(bounds.width), height: Int(bounds.height), density: density)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        reloadSettings()
    }

    // MARK: Animation

    override func animateOneFrame() {
        engine.step()
        setNeedsDisplay(bounds)
    }

    override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(bounds)

        // Squares, not dots: PatBlt fills rectangles, so no antialiasing.
        ctx.setShouldAntialias(false)
        ctx.setFillColor(NSColor.white.cgColor)

        let scale = starScale
        let height = bounds.height
        var squares: [CGRect] = []
        squares.reserveCapacity(engine.stars.count)

        for star in engine.stars {
            let p = engine.project(star)
            let side = max(1.0, CGFloat(p.size) * scale).rounded()
            // Windows measures Y downward; flip into AppKit's coordinates.
            squares.append(CGRect(x: CGFloat(p.x), y: height - CGFloat(p.y) - side,
                                  width: side, height: side))
        }
        ctx.fill(squares)
    }

    // MARK: Configuration sheet

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        guard let defaults else { return nil }
        let controller = ConfigController(defaults: defaults) { [weak self] in
            self?.reloadSettings()
        }
        configController = controller   // the sheet is not retained for us
        return controller.window
    }
}

enum Config {
    static let bundleIdentifier = "com.ilirium.Starfield"
    static let densityKey = "Density"
    static let warpKey = "WarpSpeed"
}
