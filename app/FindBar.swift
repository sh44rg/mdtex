import Cocoa
import WebKit

final class FindBar: NSView, NSSearchFieldDelegate {
    private let field = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private let options = NSPopUpButton(frame: .zero, pullsDown: true)
    private weak var webView: WKWebView?
    private var searchRevision = 0
    var onDismiss: (() -> Void)?

    private enum Option: Int, CaseIterable {
        case highlightAll = 1, matchCase, matchDiacritics, wholeWords

        var title: String {
            switch self {
            case .highlightAll: return "Highlight All"
            case .matchCase: return "Match Case"
            case .matchDiacritics: return "Match Diacritics"
            case .wholeWords: return "Whole Words"
            }
        }
    }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        field.placeholderString = "Find in Document"
        field.setAccessibilityLabel("Find in Document")
        field.delegate = self
        field.setContentHuggingPriority(.init(200), for: .horizontal)

        status.textColor = .secondaryLabelColor
        status.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        status.isHidden = true

        let steps = NSSegmentedControl(labels: ["‹", "›"], trackingMode: .momentary,
                                       target: self, action: #selector(step(_:)))
        steps.setToolTip("Previous Match (⇧⌘G)", forSegment: 0)
        steps.setToolTip("Next Match (⌘G)", forSegment: 1)
        steps.setAccessibilityLabel("Previous and Next Match")

        options.addItem(withTitle: "Options")
        options.setAccessibilityLabel("Find Options")
        options.menu?.autoenablesItems = false
        for option in Option.allCases {
            let item = NSMenuItem(title: option.title, action: #selector(toggleOption(_:)), keyEquivalent: "")
            item.target = self
            item.tag = option.rawValue
            options.menu?.addItem(item)
        }

        let done = NSButton(title: "Done", target: self, action: #selector(dismiss))
        let controls = NSStackView(views: [field, status, steps, options, done])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            controls.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var hasQuery: Bool {
        !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func focusSearchField() {
        field.selectText(nil)
        if status.isHidden && hasQuery {
            search(action: "show")
        }
    }

    func find(backwards: Bool = false) {
        search(action: backwards ? "previous" : "next")
    }

    func clearMatch() {
        search(action: "dismiss")
    }

    private func isEnabled(_ option: Option) -> Bool {
        options.menu?.item(withTag: option.rawValue)?.state == .on
    }

    private func search(action: String) {
        searchRevision += 1
        let revision = searchRevision
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if action == "dismiss" || query.isEmpty {
            status.isHidden = true
        }
        let settings: [String: Any] = [
            "action": action,
            "query": query,
            "highlightAll": isEnabled(.highlightAll),
            "matchCase": isEnabled(.matchCase),
            "matchDiacritics": isEnabled(.matchDiacritics),
            "wholeWords": isEnabled(.wholeWords),
        ]
        webView?.callAsyncJavaScript("return await window.mdtexFind?.(settings)",
                                     arguments: ["settings": settings], in: nil, in: .page) { [weak self] result in
            guard let self, self.searchRevision == revision, action != "dismiss", !query.isEmpty,
                  case let .success(value) = result, let match = value as? [String: Any],
                  let current = match["current"] as? Int, let total = match["total"] as? Int else { return }
            self.options.menu?.item(withTag: Option.highlightAll.rawValue)?.isEnabled =
                match["supportsHighlightAll"] as? Bool == true
            self.status.stringValue = total == 0 ? "No matches" : "\(current.formatted()) of \(total.formatted())"
            self.status.isHidden = false
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        if !isHidden { search(action: "show") }
    }

    func documentDidRender() {
        if !isHidden && hasQuery { search(action: "show") }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        switch command {
        case #selector(NSResponder.insertNewline(_:)):
            find(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
        default:
            return false
        }
        return true
    }

    @objc private func toggleOption(_ sender: NSMenuItem) {
        sender.state = sender.state == .on ? .off : .on
        search(action: sender.tag == Option.highlightAll.rawValue ? "highlight" : "show")
    }

    @objc private func step(_ sender: NSSegmentedControl) {
        find(backwards: sender.selectedSegment == 0)
    }

    @objc private func dismiss() {
        onDismiss?()
    }
}
