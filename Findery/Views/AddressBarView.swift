import AppKit

final class AddressBarView: NSView, NSTextFieldDelegate {

    private let textField = NSTextField()
    var onNavigate: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textField.placeholderString = "경로 입력..."
        textField.bezelStyle = .roundedBezel
        textField.delegate = self
        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func setPath(_ url: URL) {
        let home = FileSystemController.homeDirectory.path
        let path = url.path
        if path.hasPrefix(home) {
            textField.stringValue = "~" + path.dropFirst(home.count)
        } else {
            textField.stringValue = path
        }
    }

    func focus() {
        window?.makeFirstResponder(textField)
        textField.selectText(nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let path = textField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }

        if let url = FileSystemController.expandTilde(path) {
            onNavigate?(url)
        } else {
            shakeAnimation()
        }
    }

    private func shakeAnimation() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.4
        animation.values = [-8, 8, -6, 6, -4, 4, 0]
        textField.layer?.add(animation, forKey: "shake")

        textField.textColor = .systemRed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.textField.textColor = .labelColor
        }
    }
}
