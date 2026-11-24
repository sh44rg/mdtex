import Cocoa
import UniformTypeIdentifiers
import WebKit

let markdownType = UTType("net.daringfireball.markdown") ?? .plainText
let zoomKey = "zoom"
let sansSerifKey = "sansSerif"

/// Serves the bundled page at mdtex://app/… and local files (the document and
/// its images) at mdtex://app/__file__/<absolute path>.
final class ResourceHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdtex"
    static let filePrefix = "/__file__"
    static let idleURL = URL(string: "\(scheme)://app/__idle__")!
    // Keep the initial response small. Larger files use the existing file request.
    private static let embeddedSourceLimit = 128 * 1024
    private static let sourceMarker = Data("<!-- mdtex:initial-source -->".utf8)

    let webRoot: URL

    init(webRoot: URL) {
        self.webRoot = webRoot.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        var path = url.path
        if url == Self.idleURL {
            respond(task, url: url, status: 200, type: "text/html; charset=utf-8", data: Data())
            return
        }
        let fileURL: URL
        if path.hasPrefix(Self.filePrefix + "/") {
            fileURL = URL(fileURLWithPath: String(path.dropFirst(Self.filePrefix.count)))
        } else {
            if path.isEmpty || path == "/" { path = "/index.html" }
            fileURL = webRoot.appendingPathComponent(path).standardizedFileURL
            guard fileURL.path.hasPrefix(webRoot.path + "/") else {
                respond(task, url: url, status: 403, type: "text/plain", data: Data())
                return
            }
        }

        guard var data = try? Data(contentsOf: fileURL) else {
            respond(task, url: url, status: 404, type: "text/plain", data: Data())
            return
        }
        if path == "/index.html", let marker = data.range(of: Self.sourceMarker),
            let source = Self.initialSource(for: url) {
            data.replaceSubrange(marker, with: source.utf8)
        }
        respond(task, url: url, status: 200, type: Self.mimeType(for: fileURL), data: data)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private static func initialSource(for url: URL) -> String? {
        guard let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "file" })?.value,
            path.hasPrefix("/") else { return nil }

        let file = URL(fileURLWithPath: path)
        guard let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            info.isRegularFile == true, let size = info.fileSize, size <= embeddedSourceLimit,
            let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        guard let bytes = try? handle.read(upToCount: embeddedSourceLimit + 1),
            bytes.count == size else { return nil }
        var text = String(decoding: bytes, as: UTF8.self)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        guard let json = try? JSONEncoder().encode(text) else { return nil }
        // Escape markup so the browser treats the entire script element as inert data.
        let payload = String(decoding: json, as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
        return "<script id=\"initial-source\" type=\"application/json\">\(payload)</script>"
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, status: Int, type: String, data: Data) {
        let headers = [
            "Content-Type": type,
            "Content-Length": String(data.count),
            "Cache-Control": "no-store",
            // The built page loads its script and styles in CORS mode.
            "Access-Control-Allow-Origin": "*",
        ]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "md", "markdown", "mdown", "mkd", "txt", "": return "text/plain; charset=utf-8"
        case "woff2": return "font/woff2"
        default:
            return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}

/// One window showing one document (or the sample, when there is no file).
final class DocumentWindow: NSObject, NSWindowDelegate, WKNavigationDelegate {
    let window: NSWindow
    let webView: WKWebView
    let fileURL: URL?
    var onClose: ((DocumentWindow) -> Void)?
    private var webViewTop: NSLayoutConstraint
    private var findBar: FindBar?

    init(fileURL: URL?, webView: WKWebView) {
        self.fileURL = fileURL?.standardizedFileURL
        self.webView = webView
        let zoom = UserDefaults.standard.double(forKey: zoomKey)
        webView.pageZoom = zoom > 0 ? zoom : 1

        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(880, screen.width), height: min(1040, screen.height))
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let contentRect = NSWindow.contentRect(
            forFrameRect: NSRect(origin: .zero, size: size),
            styleMask: style
        )
        window = NSWindow(
            contentRect: contentRect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .white
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 420, height: 320)
        window.title = fileURL?.lastPathComponent ?? "mdtex"
        window.representedURL = fileURL
        let content = NSView()
        window.contentView = content
        webView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(webView)
        webViewTop = webView.topAnchor.constraint(equalTo: content.topAnchor)
        NSLayoutConstraint.activate([
            webViewTop,
            webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        super.init()
        window.delegate = self
        webView.navigationDelegate = self

        var page = "\(ResourceHandler.scheme)://app/index.html"
        if let path = self.fileURL?.path,
           let encoded = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            page += "?file=" + encoded
        }
        webView.load(URLRequest(url: URL(string: page)!))
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }

    func documentDidRender(name: String, fromPath: Bool) {
        window.representedURL = fromPath ? fileURL : nil
        window.title = name.isEmpty ? "mdtex" : name
        findBar?.documentDidRender()
    }

    func showFindBar() {
        if let findBar, !findBar.isHidden {
            findBar.focusSearchField()
            return
        }
        guard let content = window.contentView else { return }

        let bar: FindBar
        if let findBar {
            bar = findBar
        } else {
            bar = FindBar(webView: webView)
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.onDismiss = { [weak self] in self?.hideFindBar() }
            content.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                bar.topAnchor.constraint(equalTo: content.topAnchor),
            ])
            findBar = bar
        }
        bar.isHidden = false
        pinWebViewTop(to: bar.bottomAnchor)
        bar.focusSearchField()
    }

    func stepFind(backwards: Bool) {
        if let findBar, findBar.hasQuery {
            findBar.find(backwards: backwards)
        } else {
            showFindBar()
        }
    }

    func reload() {
        hideFindBar()
        webView.reload()
    }

    private func hideFindBar() {
        guard let findBar, !findBar.isHidden, let content = window.contentView else { return }
        findBar.isHidden = true
        pinWebViewTop(to: content.topAnchor)
        window.makeFirstResponder(webView)
        findBar.clearMatch()
    }

    private func pinWebViewTop(to anchor: NSLayoutYAxisAnchor) {
        webViewTop.isActive = false
        webViewTop = webView.topAnchor.constraint(equalTo: anchor)
        webViewTop.isActive = true
    }

    // Links to the outside world open in the default browser, not in the viewer.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = action.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.scheme == ResourceHandler.scheme, action.targetFrame != nil {
            decisionHandler(.allow)
            return
        }
        if let scheme = url.scheme, ["http", "https", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    // Development aid: MDTEX_SNAPSHOT=<path.png> saves a picture of the page and quits.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let out = ProcessInfo.processInfo.environment["MDTEX_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            webView.takeSnapshot(with: nil) { image, _ in
                if let tiff = image?.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: out))
                }
                NSApp.terminate(nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    private var documents: [DocumentWindow] = []
    private var idleWebView: WKWebView?
    private var cascadePoint = NSPoint.zero
    private lazy var handler = ResourceHandler(
        webRoot: Bundle.main.resourceURL!.appendingPathComponent("web", isDirectory: true)
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = buildMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for arg in CommandLine.arguments.dropFirst() where !arg.hasPrefix("-") {
            if FileManager.default.fileExists(atPath: arg) { show(URL(fileURLWithPath: arg)) }
        }
        // Files double-clicked in Finder arrive just before this point. If
        // nothing did, show the sample document.
        DispatchQueue.main.async {
            if self.documents.isEmpty { self.show(nil) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { show(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard documents.isEmpty else { return true }
        show(nil)
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let webView = message.webView,
              let document = documents.first(where: { $0.webView === webView }),
              let rendered = message.body as? [String: Any],
              let name = rendered["name"] as? String,
              let fromPath = rendered["fromPath"] as? Bool else { return }
        document.documentDidRender(name: name, fromPath: fromPath)
    }

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(handler, forURLScheme: ResourceHandler.scheme)
        config.userContentController.add(self, name: "documentRendered")
        setFontPreference(UserDefaults.standard.bool(forKey: sansSerifKey), on: config.userContentController)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = .white
        webView.allowsMagnification = true
        return webView
    }

    private func show(_ url: URL?) {
        let target = url?.standardizedFileURL
        if let target, let open = documents.first(where: { $0.fileURL == target }) {
            open.reload()
            open.window.makeKeyAndOrderFront(nil)
            return
        }
        let webView = idleWebView ?? makeWebView()
        idleWebView = nil
        let doc = DocumentWindow(fileURL: target, webView: webView)
        doc.onClose = { [weak self] closed in
            self?.documentClosed(closed)
        }
        if documents.isEmpty {
            doc.window.center()
            cascadePoint = .zero
        }
        cascadePoint = doc.window.cascadeTopLeft(from: cascadePoint)
        documents.append(doc)
        doc.window.makeKeyAndOrderFront(nil)
        if let target { NSDocumentController.shared.noteNewRecentDocumentURL(target) }
    }

    private func documentClosed(_ document: DocumentWindow) {
        documents.removeAll { $0 === document }
        guard documents.isEmpty else { return }

        // Keep a blank view ready for the next Finder open. A fresh view does
        // not carry the closed document's history or scroll position.
        let webView = makeWebView()
        idleWebView = webView
        webView.load(URLRequest(url: ResourceHandler.idleURL))
    }

    private var current: DocumentWindow? {
        documents.first { $0.window.isKeyWindow } ?? documents.last
    }

    // MARK: Menu actions

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [markdownType, .plainText]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls { show(url) }
        }
    }

    @objc func reloadDocument(_ sender: Any?) {
        current?.reload()
    }

    @objc func showDocumentFind(_ sender: Any?) { current?.showFindBar() }
    @objc func findNextInDocument(_ sender: Any?) { current?.stepFind(backwards: false) }
    @objc func findPreviousInDocument(_ sender: Any?) { current?.stepFind(backwards: true) }

    @objc func zoomIn(_ sender: Any?) { setZoom((current?.webView.pageZoom ?? 1) * 1.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom((current?.webView.pageZoom ?? 1) / 1.1) }
    @objc func zoomReset(_ sender: Any?) { setZoom(1) }

    private func setZoom(_ value: CGFloat) {
        let zoom = min(max(value, 0.5), 3)
        for doc in documents { doc.webView.pageZoom = zoom }
        UserDefaults.standard.set(Double(zoom), forKey: zoomKey)
    }

    private func setFontPreference(_ sansSerif: Bool, on controller: WKUserContentController) {
        controller.removeAllUserScripts()
        let script = WKUserScript(
            source: "window.mdtexSansSerif = \(sansSerif ? "true" : "false");",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        controller.addUserScript(script)
    }

    @objc func toggleSansSerif(_ sender: NSMenuItem) {
        let sansSerif = !UserDefaults.standard.bool(forKey: sansSerifKey)
        UserDefaults.standard.set(sansSerif, forKey: sansSerifKey)
        sender.state = sansSerif ? .on : .off
        let webViews = documents.map(\.webView) + (idleWebView.map { [$0] } ?? [])
        for webView in webViews {
            setFontPreference(sansSerif, on: webView.configuration.userContentController)
            webView.evaluateJavaScript("document.documentElement.classList.toggle('sans-serif', \(sansSerif ? "true" : "false"))", completionHandler: nil)
        }
    }

    @objc func makeDefaultViewer(_ sender: Any?) {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: markdownType) { error in
            DispatchQueue.main.async {
                let alert = NSAlert()
                if let error {
                    alert.alertStyle = .warning
                    alert.messageText = "Could not change the default app"
                    alert.informativeText = error.localizedDescription
                } else {
                    alert.messageText = "mdtex now opens Markdown files"
                    alert.informativeText = "Double-clicking a .md file in Finder will open it here."
                }
                alert.runModal()
            }
        }
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About mdtex", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Make Default Markdown Viewer", action: #selector(makeDefaultViewer(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide mdtex", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit mdtex", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(app, titled: "mdtex", to: main)

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        file.addItem(withTitle: "Reload", action: #selector(reloadDocument(_:)), keyEquivalent: "r")
        file.addItem(.separator())
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(file, titled: "File", to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Find…", action: #selector(showDocumentFind(_:)), keyEquivalent: "f")
        edit.addItem(withTitle: "Find Next", action: #selector(findNextInDocument(_:)), keyEquivalent: "g")
        edit.addItem(withTitle: "Find Previous", action: #selector(findPreviousInDocument(_:)), keyEquivalent: "G")
        add(edit, titled: "Edit", to: main)

        let view = NSMenu(title: "View")
        view.addItem(withTitle: "Actual Size", action: #selector(zoomReset(_:)), keyEquivalent: "0")
        view.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "=")
        view.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        view.addItem(.separator())
        let sansSerif = view.addItem(withTitle: "Use Sans Serif Font", action: #selector(toggleSansSerif(_:)), keyEquivalent: "")
        sansSerif.target = self
        sansSerif.state = UserDefaults.standard.bool(forKey: sansSerifKey) ? .on : .off
        view.addItem(.separator())
        let full = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.command, .control]
        add(view, titled: "View", to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        add(window, titled: "Window", to: main)
        NSApp.windowsMenu = window

        return main
    }

    private func add(_ menu: NSMenu, titled title: String, to main: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
