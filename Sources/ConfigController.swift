import Cocoa

/// Rebuilds the "Starfield Simulation Setup" dialog: a density stepper over
/// 10...200 and a warp speed slider over 0...10, with OK and Cancel.
final class ConfigController: NSObject {

    let window: NSWindow
    private let defaults: ScreenSaverDefaultsStore
    private let onCommit: () -> Void

    private let densityField = NSTextField(labelWithString: "")
    private let densityStepper = NSStepper()
    private let warpSlider = NSSlider()

    init(defaults: ScreenSaverDefaultsStore, onCommit: @escaping () -> Void) {
        self.defaults = defaults
        self.onCommit = onCommit
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 172),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        window.title = "Starfield Simulation Setup"
        buildContent()
        load()
    }

    private func buildContent() {
        let density = NSTextField(labelWithString: "Starfield density (10-200):")
        densityStepper.minValue = Double(StarfieldEngine.minDensity)
        densityStepper.maxValue = Double(StarfieldEngine.maxDensity)
        densityStepper.increment = 1
        densityStepper.valueWraps = false
        densityStepper.target = self
        densityStepper.action = #selector(densityChanged)
        densityField.alignment = .right
        densityField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        let densityRow = NSStackView(views: [density, densityField, densityStepper])
        densityRow.spacing = 8

        let warpLabel = NSTextField(labelWithString: "Warp speed:")
        warpSlider.minValue = Double(StarfieldEngine.minWarp)
        warpSlider.maxValue = Double(StarfieldEngine.maxWarp)
        warpSlider.numberOfTickMarks = StarfieldEngine.maxWarp + 1
        warpSlider.allowsTickMarkValuesOnly = true
        let warpRow = NSStackView(views: [warpLabel, warpSlider])
        warpRow.spacing = 8

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "OK", target: self, action: #selector(commit))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, ok])
        buttons.spacing = 12

        let stack = NSStackView(views: [densityRow, warpRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView(frame: window.contentLayoutRect)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            warpRow.widthAnchor.constraint(equalTo: densityRow.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: densityRow.widthAnchor),
        ])
        window.contentView = content
    }

    private func load() {
        let density = defaults.integer(forKey: Config.densityKey)
        densityStepper.integerValue = density
        densityField.stringValue = "\(density)"
        warpSlider.integerValue = defaults.integer(forKey: Config.warpKey)
    }

    @objc private func densityChanged() {
        densityField.stringValue = "\(densityStepper.integerValue)"
    }

    @objc private func commit() {
        defaults.set(densityStepper.integerValue, forKey: Config.densityKey)
        defaults.set(warpSlider.integerValue, forKey: Config.warpKey)
        _ = defaults.synchronize()
        onCommit()
        close()
    }

    @objc private func cancel() { close() }

    private func close() {
        guard let sheetParent = window.sheetParent else {
            window.orderOut(nil)
            return
        }
        sheetParent.endSheet(window)
    }
}

/// The bits of ScreenSaverDefaults the sheet needs, so the same controller can
/// be driven by plain UserDefaults in the standalone preview app.
protocol ScreenSaverDefaultsStore: AnyObject {
    func integer(forKey key: String) -> Int
    func set(_ value: Int, forKey key: String)
    func synchronize() -> Bool
}

extension UserDefaults: ScreenSaverDefaultsStore {}
