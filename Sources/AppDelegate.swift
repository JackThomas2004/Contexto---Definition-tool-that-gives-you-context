// AppDelegate.swift — Menu bar app lifecycle and Services handler
import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Properties
    var statusItem: NSStatusItem?
    var definitionWindowController: DefinitionWindowController?
    var preferencesWindowController: PreferencesWindowController?

    /// The last non-Contexto app that was frontmost.
    /// When a Services call arrives macOS briefly makes Contexto active, so
    /// NSWorkspace.frontmostApplication at that moment returns *us*, not the
    /// app the user was reading.  We track the previous app via KVO so we
    /// always read context from the right source.
    private var previousFrontApp: NSRunningApplication?
    private var frontAppObserver: NSKeyValueObservation?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Run as a menu-bar-only app (no Dock icon)
        _ = NSApp.setActivationPolicy(.accessory)

        // Register this object as the handler for macOS Services calls
        NSApp.servicesProvider = self

        setupStatusItem()

        // Keep a rolling record of which app was last in front (excluding ourselves)
        frontAppObserver = NSWorkspace.shared.observe(
            \.frontmostApplication, options: [.new]
        ) { [weak self] _, change in
            guard let app = change.newValue ?? nil,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self?.previousFrontApp = app
        }
    }

    // MARK: - Status Item (Menu Bar Icon)

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = drawMenuBarIcon()
            button.image?.isTemplate = true   // Adapts to dark/light menu bar
            button.toolTip = "Contexto — AI Word Definer"
        }

        buildMenu()
    }

    /// Draws the Contexto "C·" symbol at 18×18 for the menu bar.
    private func drawMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let cx = rect.midX
            let cy = rect.midY
            let radius: CGFloat = 7.5
            let lineWidth: CGFloat = 2.2

            // Arc path for the "C"
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: cx - 0.5, y: cy),
                           radius: radius,
                           startAngle: 40,
                           endAngle: 320,
                           clockwise: false)
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()

            // Small dot — the "definition" indicator
            let dotR: CGFloat = 1.8
            let dotCenter = NSPoint(x: cx + radius * 0.55, y: cy)
            let dotPath = NSBezierPath(ovalIn: NSRect(
                x: dotCenter.x - dotR,
                y: dotCenter.y - dotR,
                width: dotR * 2,
                height: dotR * 2
            ))
            NSColor.black.setFill()
            dotPath.fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    private func buildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "Contexto", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Define from Clipboard",
                     action: #selector(defineFromClipboard),
                     keyEquivalent: "d")

        menu.addItem(.separator())

        menu.addItem(withTitle: "How to Use",
                     action: #selector(showHowToUse),
                     keyEquivalent: "")

        menu.addItem(withTitle: "Preferences…",
                     action: #selector(openPreferences),
                     keyEquivalent: ",")

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit Contexto",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - macOS Services Handler

    /// Called by macOS when the user selects "Define with Contexto" from the
    /// Services sub-menu (right-click → Services → Define with Contexto).
    @objc func handleDefineWithContexto(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) {
        guard let selectedText = pasteboard.string(forType: .string),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        let trimmed    = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceApp  = previousFrontApp   // captured before we show any UI

        DispatchQueue.main.async { self.showLoading(for: trimmed) }

        ContextService.shared.getContext(selectedText: trimmed, sourceApp: sourceApp) { [weak self] pageInfo in
            guard let self = self else { return }

            let apiKey = UserDefaults.standard.string(forKey: "contextoAPIKey") ?? ""
            guard !apiKey.isEmpty else {
                DispatchQueue.main.async {
                    self.showResult(
                        term: trimmed,
                        definition: "⚠️  No API key set.\n\nOpen Contexto from the menu bar → Preferences and enter your OpenAI API key to get started."
                    )
                }
                return
            }

            AIService.shared.define(term: trimmed, pageInfo: pageInfo, apiKey: apiKey) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let def):
                        self.showResult(term: trimmed, definition: def, pageInfo: pageInfo)
                    case .failure(let err):
                        self.showResult(term: trimmed, definition: "Error: \(err.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Menu Actions

    @objc private func defineFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            let alert = NSAlert()
            alert.messageText = "Nothing to Define"
            alert.informativeText = "Copy some text first, then choose \"Define from Clipboard\"."
            alert.runModal()
            return
        }

        let trimmed   = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceApp = previousFrontApp
        showLoading(for: trimmed)

        let apiKey = UserDefaults.standard.string(forKey: "contextoAPIKey") ?? ""
        guard !apiKey.isEmpty else {
            showResult(term: trimmed, definition: "⚠️  No API key set. Open Preferences from the Contexto menu.")
            return
        }

        ContextService.shared.getContext(selectedText: trimmed, sourceApp: sourceApp) { [weak self] pageInfo in
            AIService.shared.define(term: trimmed, pageInfo: pageInfo, apiKey: apiKey) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let def):
                        self?.showResult(term: trimmed, definition: def, pageInfo: pageInfo)
                    case .failure(let err):
                        self?.showResult(term: trimmed, definition: "Error: \(err.localizedDescription)")
                    }
                }
            }
        }
    }

    @objc private func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showHowToUse() {
        let alert = NSAlert()
        alert.messageText = "How to Use Contexto"
        alert.informativeText = """
        1. While reading an article online, highlight any word or phrase you don't understand.
        2. Right-click the highlighted text.
        3. Go to Services → "Define with Contexto".
        4. A floating window will appear with an AI-generated definition tailored to the article.

        ─────────────────────────────
        Tip: If you don't see the Services option, go to:
        System Settings → Keyboard → Keyboard Shortcuts → Services
        and make sure "Define with Contexto" is ticked.

        You can also copy text and use "Define from Clipboard" in the Contexto menu.
        """
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }

    // MARK: - Helpers

    private func showLoading(for term: String) {
        if definitionWindowController == nil {
            definitionWindowController = DefinitionWindowController()
        }
        definitionWindowController?.showLoading(term: term)
    }

    private func showResult(term: String, definition: String, pageInfo: PageInfo? = nil) {
        if definitionWindowController == nil {
            definitionWindowController = DefinitionWindowController()
        }
        definitionWindowController?.showDefinition(term: term, definition: definition, pageInfo: pageInfo)
    }
}
