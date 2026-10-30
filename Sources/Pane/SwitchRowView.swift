import AppKit

/// A menu row for an on/off setting: icon, title, subtitle and a switch. Clicking the row
/// or the switch toggles it in place and keeps the menu open, so the subtitle can update.
final class SwitchRowView: NSView {
    /// Called with the new state; returns the subtitle to show for it.
    var onChange: ((Bool) -> String?)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()
    private var isHovered = false { didSet { needsDisplay = true } }

    var isOn: Bool {
        get { toggle.state == .on }
        set { toggle.state = newValue ? .on : .off }
    }

    init(title: String, subtitle: String?, icon: NSImage?, isOn: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: subtitle == nil ? 26 : 40))
        autoresizingMask = [.width]

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .labelColor
        titleLabel.font = .menuFont(ofSize: 0)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        toggle.controlSize = .mini
        toggle.target = self
        toggle.action = #selector(switchFlipped)

        [iconView, titleLabel, subtitleLabel, toggle].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            // Lines up with the icons and titles of the regular menu items.
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        if subtitle == nil {
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        } else {
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4).isActive = true
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 0).isActive = true
        }
        update(title: title, subtitle: subtitle, icon: icon, isOn: isOn)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(title: String, subtitle: String?, icon: NSImage?, isOn: Bool) {
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        iconView.image = icon
        self.isOn = isOn
    }

    @objc private func switchFlipped() {
        if let subtitle = onChange?(isOn) { subtitleLabel.stringValue = subtitle }
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        isOn.toggle()
        switchFlipped()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isHovered = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered else { return }
        // A soft row highlight like the menu's own, inset to match its rounded selection.
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

/// A menu row with a slider, e.g. how dark No peek makes other windows.
final class SliderRowView: NSView {
    var onChange: ((Double) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private let format: (Double) -> String

    init(title: String, value initial: Double, range: ClosedRange<Double>, format: @escaping (Double) -> String) {
        slider = NSSlider(value: initial, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        self.format = format
        super.init(frame: NSRect(x: 0, y: 0, width: 340, height: 30))
        autoresizingMask = [.width]
        label.stringValue = title
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        value.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.stringValue = format(initial)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(moved)
        [label, slider, value].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 54),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 10),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            value.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            value.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            value.centerYAnchor.constraint(equalTo: centerYAnchor),
            value.widthAnchor.constraint(equalToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func moved() {
        value.stringValue = format(slider.doubleValue)
        onChange?(slider.doubleValue)
    }
}
