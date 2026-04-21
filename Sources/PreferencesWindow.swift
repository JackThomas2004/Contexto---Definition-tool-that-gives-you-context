// PreferencesWindow.swift — API key and settings
import AppKit

class PreferencesWindowController: NSWindowController {

    private var apiKeyField: NSSecureTextField!
    private var statusLabel: NSTextField!

    init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 290),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Contexto — Preferences"
        win.center()
        super.init(window: win)
        buildUI()
    }
    required init?(coder: NSCoder) { fatalError("Not implemented") }

    // MARK: - UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }

        let pad: CGFloat = 28

        // ── Title ────────────────────────────────────────────────────────────
        let titleLabel = NSTextField(labelWithString: "Contexto Preferences")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 18)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Context-aware AI definitions while you read")
        subtitleLabel.font = NSFont.systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(subtitleLabel)

        // ── Separator ─────────────────────────────────────────────────────────
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(sep)

        // ── API Key ───────────────────────────────────────────────────────────
        let keyLabel = NSTextField(labelWithString: "OpenAI API Key")
        keyLabel.font = NSFont.boldSystemFont(ofSize: 13)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(keyLabel)

        let helpLabel = NSTextField(labelWithString: "Get a key at platform.openai.com → API keys")
        helpLabel.font = NSFont.systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(helpLabel)

        apiKeyField = NSSecureTextField(frame: .zero)
        apiKeyField.placeholderString = "sk-proj-..."
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.stringValue = UserDefaults.standard.string(forKey: "contextoAPIKey") ?? ""
        cv.addSubview(apiKeyField)

        // ── Status ────────────────────────────────────────────────────────────
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(statusLabel)

        // ── Buttons ───────────────────────────────────────────────────────────
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(save))
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(saveBtn)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelWindow))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1B}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(cancelBtn)

        // ── Layout ────────────────────────────────────────────────────────────
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: pad),
            titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),

            sep.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 14),
            sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),

            keyLabel.topAnchor.constraint(equalTo: sep.bottomAnchor, constant: 18),
            keyLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),

            helpLabel.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 3),
            helpLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),

            apiKeyField.topAnchor.constraint(equalTo: helpLabel.bottomAnchor, constant: 8),
            apiKeyField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),
            apiKeyField.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
            apiKeyField.heightAnchor.constraint(equalToConstant: 26),

            statusLabel.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: pad),

            saveBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad),
            saveBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -pad),
            saveBtn.widthAnchor.constraint(equalToConstant: 80),

            cancelBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -pad),
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            cancelBtn.widthAnchor.constraint(equalToConstant: 80),
        ])
    }

    // MARK: - Actions

    @objc private func save() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            statusLabel.stringValue = "⚠️  Please enter your API key."
            statusLabel.textColor   = .systemOrange
            return
        }
        UserDefaults.standard.set(key, forKey: "contextoAPIKey")
        statusLabel.stringValue = "✓  Saved!"
        statusLabel.textColor   = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.close()
        }
    }

    @objc private func cancelWindow() { close() }
}
