// DefinitionWindow.swift — Floating panel that shows AI-generated definitions
import AppKit

// MARK: - Colours & Layout Constants

private enum Design {
    static let headerColor   = NSColor(red: 0.11, green: 0.39, blue: 0.79, alpha: 1)
    static let headerHeight:  CGFloat = 34
    static let padding:       CGFloat = 16
    static let minHeight:     CGFloat = 180
    static let windowWidth:   CGFloat = 430
}

// MARK: - DefinitionWindowController

class DefinitionWindowController: NSWindowController {

    // MARK: Subviews
    private var termLabel:        NSTextField!
    private var definitionLabel:  NSTextField!
    private var loadingSpinner:   NSProgressIndicator!
    private var footerLabel:      NSTextField!
    private var copyButton:       NSButton!
    private var currentDefinition = ""

    // MARK: - Initialiser

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Design.windowWidth, height: Design.minHeight),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.title               = ""
        panel.isFloatingPanel     = true
        panel.level               = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate   = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility     = .hidden
        panel.minSize             = NSSize(width: 320, height: Design.minHeight)

        super.init(window: panel)
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    // MARK: - UI Construction

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        cv.wantsLayer = true

        // ── Header bar ──────────────────────────────────────────────────────
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = Design.headerColor.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(header)

        let appLabel = NSTextField(labelWithString: "◉  Contexto")
        appLabel.textColor = .white
        appLabel.font = NSFont.boldSystemFont(ofSize: 12)
        appLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(appLabel)

        // ── Term ────────────────────────────────────────────────────────────
        termLabel = NSTextField(labelWithString: "")
        termLabel.font = NSFont.boldSystemFont(ofSize: 15)
        termLabel.textColor = NSColor.labelColor
        termLabel.lineBreakMode = .byTruncatingTail
        termLabel.maximumNumberOfLines = 2
        termLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(termLabel)

        // ── Definition ──────────────────────────────────────────────────────
        definitionLabel = NSTextField(wrappingLabelWithString: "")
        definitionLabel.font = NSFont.systemFont(ofSize: 13)
        definitionLabel.textColor = NSColor.secondaryLabelColor
        definitionLabel.isSelectable = true
        definitionLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(definitionLabel)

        // ── Loading spinner ─────────────────────────────────────────────────
        loadingSpinner = NSProgressIndicator()
        loadingSpinner.style = .spinning
        loadingSpinner.isIndeterminate = true
        loadingSpinner.isHidden = true
        loadingSpinner.controlSize = .regular
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(loadingSpinner)

        // ── Footer ──────────────────────────────────────────────────────────
        footerLabel = NSTextField(labelWithString: "")
        footerLabel.font = NSFont.systemFont(ofSize: 10)
        footerLabel.textColor = NSColor.tertiaryLabelColor
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(footerLabel)

        // ── Copy button ─────────────────────────────────────────────────────
        copyButton = NSButton(title: "Copy", target: self, action: #selector(copyToClipboard))
        copyButton.bezelStyle = .rounded
        copyButton.font = NSFont.systemFont(ofSize: 11)
        copyButton.isHidden = true
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(copyButton)

        // ── Constraints ─────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            // Header
            header.topAnchor.constraint(equalTo: cv.topAnchor),
            header.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: Design.headerHeight),

            appLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            appLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),

            // Term
            termLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            termLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: Design.padding),
            termLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -Design.padding),

            // Definition
            definitionLabel.topAnchor.constraint(equalTo: termLabel.bottomAnchor, constant: 8),
            definitionLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: Design.padding),
            definitionLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -Design.padding),

            // Spinner (centred below term when loading)
            loadingSpinner.topAnchor.constraint(equalTo: termLabel.bottomAnchor, constant: 18),
            loadingSpinner.centerXAnchor.constraint(equalTo: cv.centerXAnchor),

            // Footer
            footerLabel.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -8),
            footerLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: Design.padding),

            // Copy button
            copyButton.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -6),
            copyButton.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
        ])
    }

    // MARK: - Public API

    func showLoading(term: String) {
        termLabel.stringValue  = "\"\(cleanTerm(term))\""
        definitionLabel.stringValue = ""
        definitionLabel.isHidden    = true
        loadingSpinner.isHidden     = false
        loadingSpinner.startAnimation(nil)
        footerLabel.stringValue     = "Asking OpenAI..."
        copyButton.isHidden         = true

        positionNearCursor()
        showWindow(nil)
    }

    func showDefinition(term: String, definition: String, pageInfo: PageInfo? = nil) {
        currentDefinition = definition

        termLabel.stringValue       = "\"\(cleanTerm(term))\""
        definitionLabel.stringValue = definition
        definitionLabel.isHidden    = false
        loadingSpinner.stopAnimation(nil)
        loadingSpinner.isHidden     = true
        copyButton.isHidden         = false

        // Show which document was read so the user can verify context is correct
        if let info = pageInfo, !info.title.isEmpty {
            let source = info.title.count > 40
                ? String(info.title.prefix(37)) + "…"
                : info.title
            footerLabel.stringValue = "Source: \(source)"
        } else {
            footerLabel.stringValue = "Powered by OpenAI · Contexto"
        }

        resizeToFitContent(definition)

        if window?.isVisible == false {
            positionNearCursor()
        }
        showWindow(nil)
    }

    // MARK: - Actions

    @objc private func copyToClipboard() {
        let text = "\(termLabel.stringValue)\n\n\(currentDefinition)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copyButton.title = "Copied ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.copyButton.title = "Copy"
        }
    }

    // MARK: - Private Helpers

    private func cleanTerm(_ t: String) -> String {
        // Remove leading/trailing whitespace and truncate long selections
        let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.count > 80 ? String(s.prefix(77)) + "…" : s
    }

    private func resizeToFitContent(_ text: String) {
        guard let window = window else { return }

        let availableWidth = Design.windowWidth - Design.padding * 2

        // Measure term label (bold 15pt, max 2 lines)
        let termAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 15)]
        let termRect = (termLabel.stringValue as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: 600),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: termAttrs
        )
        // Cap to 2 lines worth of height
        let twoLineHeight: CGFloat = NSFont.boldSystemFont(ofSize: 15).pointSize * 2.6
        let termHeight = min(ceil(termRect.height) + 2, twoLineHeight)

        // Measure definition label (regular 13pt, unlimited lines)
        let defAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13)]
        let defRect = (text as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: defAttrs
        )
        let defHeight = ceil(defRect.height) + 4  // small buffer to avoid clipping

        // header(34) + gap(14) + term + gap(8) + definition + footer area(40)
        // footer area: footer label ~14pt + copy button ~24pt + padding = ~40
        let totalHeight = Design.headerHeight + 14 + termHeight + 8 + defHeight + 40
        let clampedHeight = max(Design.minHeight, min(totalHeight, 600))

        var frame = window.frame
        let delta  = clampedHeight - frame.height
        frame.origin.y -= delta   // grow upward so position doesn't jump
        frame.size.height = clampedHeight
        window.setFrame(frame, display: true, animate: true)
    }

    private func positionNearCursor() {
        guard let window = window, let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let sf    = screen.visibleFrame
        var x = mouse.x + 12
        var y = mouse.y - window.frame.height - 12

        if x + window.frame.width  > sf.maxX { x = mouse.x - window.frame.width - 12 }
        if y < sf.minY                        { y = mouse.y + 20 }
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
