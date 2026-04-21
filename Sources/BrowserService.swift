// ContextService.swift — Reads context from the frontmost app.
// Primary method: JavaScript via AppleScript.
// Fallback: direct HTTP fetch + HTML stripping (works regardless of browser settings).
import AppKit
import ApplicationServices
import PDFKit

// MARK: - Bundle ID sets

private let pdfViewerBundleIDs: Set<String> = [
    "com.apple.Preview",
    "com.adobe.Acrobat",
    "com.adobe.Reader",
    "com.adobe.acrobat.pro"
]

private let browserBundleIDs: Set<String> = [
    "com.apple.Safari",
    "com.google.Chrome",
    "com.brave.Browser",
    "company.thebrowser.Browser",
    "com.microsoft.edgemac",
    "org.mozilla.firefox",
    "com.opera.Opera",
    "com.vivaldi.Vivaldi"
]

// MARK: - ContextService

class ContextService {
    static let shared = ContextService()
    private init() {}

    func getContext(selectedText: String,
                    sourceApp: NSRunningApplication? = nil,
                    completion: @escaping (PageInfo?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // For LSUIElement apps, macOS does NOT make Contexto the frontmost app
            // when handling a Services call — the originating app stays in front.
            // So NSWorkspace.frontmostApplication is reliable and should be preferred.
            // Only fall back to the caller-supplied app if frontmost somehow returns
            // Contexto itself (shouldn't happen, but guards against edge cases).
            let currentFront = NSWorkspace.shared.frontmostApplication
            let frontApp: NSRunningApplication
            if let app = currentFront,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                frontApp = app          // use what's actually in front right now
            } else if let supplied = sourceApp {
                frontApp = supplied     // fallback to tracked previous app
            } else {
                completion(nil); return
            }

            let bundleID = frontApp.bundleIdentifier ?? ""
            let appName  = frontApp.localizedName    ?? "Unknown App"
            let pid      = frontApp.processIdentifier

            if browserBundleIDs.contains(bundleID) {
                self.browserContext(bundleID: bundleID, selectedText: selectedText, pid: pid) { info in
                    completion(info)
                }
                return
            }

            if pdfViewerBundleIDs.contains(bundleID) {
                if let info = self.pdfContext(bundleID: bundleID, selectedText: selectedText, pid: pid) {
                    completion(info); return
                }
            }

            if bundleID == "com.microsoft.Word" {
                if let info = self.wordContext() { completion(info); return }
            }
            if bundleID == "com.apple.iWork.Pages" {
                if let info = self.pagesContext() { completion(info); return }
            }
            if bundleID == "com.apple.Notes" {
                if let info = self.notesContext() { completion(info); return }
            }

            if let info = self.accessibilityContext(pid: pid,
                                                    appName: appName,
                                                    selectedText: selectedText) {
                completion(info); return
            }

            completion(PageInfo(url: "", title: appName, content: "", browser: appName))
        }
    }

    // MARK: - Accessibility permission

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    static func requestAccessibilityPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Browser routing

    private func browserContext(bundleID: String, selectedText: String, pid: pid_t,
                                completion: @escaping (PageInfo?) -> Void) {
        // Try AX first — works with only Accessibility permission, no Automation dialog.
        // AppleScript is tried second; it also provides JS page body when available.
        let axURL                         = documentURLviaAX(pid: pid)
        let (asURL, asTitle, jsContent)   = browserMetaAndJS(bundleID: bundleID)

        let url   = axURL ?? asURL
        let title = asTitle ?? ""

        guard let url = url, !url.isEmpty else { completion(nil); return }

        // If AppleScript returned JS body, use it (richest source)
        if let js = jsContent, !js.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let focused = surroundingContext(in: js, around: selectedText, radius: 1500)
            completion(PageInfo(url: url, title: title, content: focused, browser: browserName(bundleID)))
            return
        }

        // Otherwise fetch the page over HTTP (no browser permission needed at all)
        fetchPageContent(url: url, selectedText: selectedText) { content in
            completion(PageInfo(url: url, title: title, content: content, browser: self.browserName(bundleID)))
        }
    }

    /// Returns (url, title, jsBodyText?) by running AppleScript against the active browser tab.
    private func browserMetaAndJS(bundleID: String) -> (String?, String?, String?) {
        switch bundleID {
        case "com.apple.Safari":
            let meta = run("""
            tell application "Safari"
                if it is running then
                    set t to current tab of front window
                    return (URL of t) & "|||" & (name of t)
                end if
            end tell
            """)
            guard let meta = meta, meta.contains("|||") else { return (nil, nil, nil) }
            let parts = meta.components(separatedBy: "|||")
            let url   = parts[0]
            let title = parts.count > 1 ? parts[1] : ""
            // Safari requires Develop > Allow JavaScript from Apple Events — may be empty
            let js = run("""
            tell application "Safari"
                return do JavaScript \
                "(function(){var el=document.querySelector('article,main,[role=main],.post-content,.entry-content,#content,.content');return(el||document.body).innerText.substring(0,10000);})()" \
                in current tab of front window
            end tell
            """)
            return (url, title, js)

        default: // Chrome, Brave, Edge, etc.
            let name   = browserName(bundleID)
            let result = run("""
            tell application "\(name)"
                if it is running then
                    set t to active tab of front window
                    set u to URL of t
                    set ttl to title of t
                    set body to execute t javascript \
                    "(function(){var el=document.querySelector('article,main,[role=main],.post-content,.entry-content,#content,.content');return(el||document.body).innerText.substring(0,10000);})()"
                    return u & "|||" & ttl & "|||" & body
                end if
            end tell
            """)
            guard let result = result, result.contains("|||") else { return (nil, nil, nil) }
            let p = result.components(separatedBy: "|||")
            return (p[0], p.count > 1 ? p[1] : "", p.count > 2 ? p[2] : "")
        }
    }

    private func browserName(_ bundleID: String) -> String {
        switch bundleID {
        case "com.apple.Safari":              return "Safari"
        case "com.google.Chrome":             return "Google Chrome"
        case "com.brave.Browser":             return "Brave Browser"
        case "com.microsoft.edgemac":         return "Microsoft Edge"
        case "company.thebrowser.Browser":    return "Arc"
        default:                              return "Browser"
        }
    }

    // MARK: - HTTP fallback (fetches page directly, no browser JS needed)

    private func fetchPageContent(url: String, selectedText: String, completion: @escaping (String) -> Void) {
        guard let pageURL = URL(string: url) else { completion(""); return }

        var req = URLRequest(url: pageURL)
        req.timeoutInterval = 8
        // Use a real User-Agent so servers don't block the request
        req.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        URLSession.shared.dataTask(with: req) { data, _, error in
            guard let data = data, error == nil,
                  let html = String(data: data, encoding: .utf8)
                          ?? String(data: data, encoding: .isoLatin1)
            else { completion(""); return }

            // Get full text then focus the window around where the selected word appears
            let fullText = self.extractText(from: html)
            let focused  = self.surroundingContext(in: fullText, around: selectedText, radius: 1500)
            completion(focused)
        }.resume()
    }

    /// Strips HTML tags and returns clean readable text (up to 10 000 chars).
    private func extractText(from html: String) -> String {
        var text = html

        // Remove invisible blocks first
        for pattern in [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<nav[^>]*>[\\s\\S]*?</nav>",
            "<header[^>]*>[\\s\\S]*?</header>",
            "<footer[^>]*>[\\s\\S]*?</footer>",
            "<!--[\\s\\S]*?-->"
        ] {
            if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = re.stringByReplacingMatches(
                    in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            }
        }

        // Strip remaining tags
        if let re = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = re.stringByReplacingMatches(
                in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&ndash;", with: "–")

        // Collapse whitespace
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return String(words.joined(separator: " ").prefix(10000))
    }

    // MARK: - Microsoft Word

    private func wordContext() -> PageInfo? {
        let result = run("""
        tell application "Microsoft Word"
            if it is running then
                set docTitle to name of active document
                set docText to content of text object of active document
                set trimmed to text 1 thru (min(2500, count characters of docText)) of docText
                return docTitle & "|||" & trimmed
            end if
        end tell
        """)
        guard let result = result, result.contains("|||") else { return nil }
        let p = result.components(separatedBy: "|||")
        return PageInfo(url: "", title: p[0], content: p.count > 1 ? p[1] : "", browser: "Microsoft Word")
    }

    // MARK: - Apple Pages

    private func pagesContext() -> PageInfo? {
        let result = run("""
        tell application "Pages"
            if it is running then
                set docName to name of front document
                set docText to body text of front document
                set trimmed to text 1 thru (min(2500, count characters of docText)) of docText
                return docName & "|||" & trimmed
            end if
        end tell
        """)
        guard let result = result, result.contains("|||") else { return nil }
        let p = result.components(separatedBy: "|||")
        return PageInfo(url: "", title: p[0], content: p.count > 1 ? p[1] : "", browser: "Pages")
    }

    // MARK: - Apple Notes

    private func notesContext() -> PageInfo? {
        let result = run("""
        tell application "Notes"
            if it is running then
                set n to first note of default account
                set noteTitle to name of n
                set noteBody to plaintext of n
                set trimmed to text 1 thru (min(2500, count characters of noteBody)) of noteBody
                return noteTitle & "|||" & trimmed
            end if
        end tell
        """)
        guard let result = result, result.contains("|||") else { return nil }
        let p = result.components(separatedBy: "|||")
        return PageInfo(url: "", title: p[0], content: p.count > 1 ? p[1] : "", browser: "Notes")
    }

    // MARK: - PDF reading via PDFKit

    private func pdfContext(bundleID: String, selectedText: String, pid: pid_t) -> PageInfo? {
        // Four-level priority chain for identifying which PDF the user is reading:
        //
        //   1. kAXDocument on the frontmost window — gives the exact file:// URL.
        //      Needs only Accessibility (already granted). Most reliable; works even
        //      when multiple PDFs are open because it reads the *active* window.
        //
        //   2. AppleScript "file of front document" — also precise, but requires
        //      Automation permission (one-time dialog; this call returns nil while
        //      the dialog is shown, but the next call succeeds).
        //
        //   3. Window-title matching against lsof results — Preview's window title
        //      is the filename of the document it shows.  We match that title against
        //      the filenames in the lsof output to pick the active document without
        //      needing any special permissions.  This is the key fix for the case
        //      where two open PDFs share the same words.
        //
        //   4. Text-search across all open PDFs — last resort when the above fail
        //      (e.g. Preview hasn't exposed a window title yet, or the PDF is scanned
        //      and contains no machine-readable text).

        // ── Priority 1: AXDocument URL ───────────────────────────────────────
        if let axURL = documentURLviaAX(pid: pid),
           axURL.hasPrefix("file://"),
           let path = URL(string: axURL)?.path,
           FileManager.default.fileExists(atPath: path) {
            return readPDFContext(from: [path], selectedText: selectedText)
        }

        // ── Priority 2: AppleScript exact path ───────────────────────────────
        if let path = pdfPathViaAppleScript(bundleID: bundleID),
           FileManager.default.fileExists(atPath: path) {
            return readPDFContext(from: [path], selectedText: selectedText)
        }

        // Collect all open PDFs once — used by both remaining priorities.
        let allPDFs = openPDFsViaLsof(pid: pid)
        guard !allPDFs.isEmpty else { return nil }

        // ── Priority 3: Window-title match ───────────────────────────────────
        // Preview sets its window title to the document's display name.
        // macOS may hide the ".pdf" extension depending on Finder preferences,
        // so we compare both with and without the extension.
        if let winTitle = activeWindowTitle(pid: pid), !winTitle.isEmpty {
            let titleLower = winTitle.lowercased()
            let matched = allPDFs.first { path in
                let url              = URL(fileURLWithPath: path)
                let filename         = url.lastPathComponent.lowercased()              // "paper.pdf"
                let filenameNoExt    = url.deletingPathExtension().lastPathComponent.lowercased() // "paper"
                return filename == titleLower
                    || filenameNoExt == titleLower
                    || filename == titleLower + ".pdf"
            }
            if let path = matched {
                return readPDFContext(from: [path], selectedText: selectedText)
            }
        }

        // ── Priority 4: Text-search across all open PDFs ─────────────────────
        return readPDFContext(from: allPDFs, selectedText: selectedText)
    }

    /// Asks the active PDF viewer (via AppleScript) for the POSIX path of its
    /// front document.  Returns nil immediately if the Automation permission
    /// dialog is still pending — the caller should fall through to the next
    /// priority level, and the next attempt will succeed after the user allows.
    private func pdfPathViaAppleScript(bundleID: String) -> String? {
        let script: String
        switch bundleID {
        case "com.apple.Preview":
            script = "tell application \"Preview\"\nif it is running then\nreturn POSIX path of (file of front document)\nend if\nend tell"
        case "com.adobe.Acrobat", "com.adobe.acrobat.pro":
            script = "tell application \"Adobe Acrobat\"\nif it is running then\nreturn POSIX path of (file of front document)\nend if\nend tell"
        case "com.adobe.Reader":
            script = "tell application \"Adobe Acrobat Reader DC\"\nif it is running then\nreturn POSIX path of (file of front document)\nend if\nend tell"
        default:
            return nil
        }
        guard let raw = run(script) else { return nil }
        let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? nil : p
    }

    /// Reads the title of the app's frontmost window via the Accessibility API.
    /// For Preview this is the PDF's display name (e.g. "economics_paper.pdf"
    /// or "economics_paper" if macOS hides the extension).
    /// Requires only Accessibility permission — no Automation dialog.
    private func activeWindowTitle(pid: pid_t) -> String? {
        guard ContextService.hasAccessibilityPermission else { return nil }
        let app = AXUIElementCreateApplication(pid)
        for attr in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] as [CFString] {
            var winRef: AnyObject?
            guard AXUIElementCopyAttributeValue(app, attr, &winRef) == .success,
                  CFGetTypeID(winRef as CFTypeRef) == AXUIElementGetTypeID()
            else { continue }
            let window = winRef as! AXUIElement
            var titleRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, !title.isEmpty {
                return title
            }
        }
        return nil
    }

    /// Extracts text from each candidate PDF path and returns a PageInfo built
    /// from whichever document actually contains the selected word.
    /// Falls back to the first readable document when none match (e.g. scanned PDFs).
    private func readPDFContext(from paths: [String], selectedText: String) -> PageInfo? {
        var fallback: PageInfo? = nil

        for path in paths {
            let fileURL = URL(fileURLWithPath: path)
            guard let pdf = PDFDocument(url: fileURL) else { continue }

            var fullText = ""
            for i in 0..<pdf.pageCount {
                guard fullText.count < 15000 else { break }
                if let t = pdf.page(at: i)?.string { fullText += t + "\n" }
            }
            guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let title   = fileURL.lastPathComponent
            let focused = surroundingContext(in: fullText, around: selectedText, radius: 1500)
            let info    = PageInfo(url: fileURL.absoluteString, title: title,
                                   content: focused, browser: "Preview")

            if fullText.range(of: selectedText, options: .caseInsensitive) != nil {
                return info   // exact document found — return immediately
            }

            if fallback == nil { fallback = info }
        }

        return fallback
    }

    /// Returns ALL PDF paths currently open by the given process via lsof.
    /// Requires no special macOS permissions.
    private func openPDFsViaLsof(pid: pid_t) -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments     = ["-p", "\(pid)", "-Fn"]

        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError  = Pipe()

        guard (try? task.run()) != nil else { return [] }
        task.waitUntilExit()

        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""

        var results: [String] = []
        for line in output.components(separatedBy: "\n") {
            guard line.hasPrefix("n") else { continue }
            let p = String(line.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            guard p.hasPrefix("/"), p.lowercased().hasSuffix(".pdf"),
                  FileManager.default.fileExists(atPath: p) else { continue }
            if !results.contains(p) { results.append(p) }
        }
        return results
    }

    // MARK: - Accessibility API (fallback for other apps)

    private func accessibilityContext(pid: pid_t,
                                      appName: String,
                                      selectedText: String) -> PageInfo? {
        guard ContextService.hasAccessibilityPermission else { return nil }

        let appElement = AXUIElementCreateApplication(pid)

        let windowTitle = axElement(appElement, kAXMainWindowAttribute as String)
            .flatMap { axStringAttribute($0, kAXTitleAttribute as String) }
            ?? appName

        let fullText = collectText(from: appElement, limit: 3000)
        guard !fullText.isEmpty else { return nil }

        let context = surroundingContext(in: fullText, around: selectedText, radius: 600)
        return PageInfo(url: "", title: windowTitle, content: context, browser: appName)
    }

    // MARK: - AX document-URL helper

    /// Reads the current document URL from the app's main window via the
    /// Accessibility API (kAXDocument attribute).  Works for Safari, Chrome,
    /// Edge, and document-based apps like Preview — without needing Automation
    /// permission.  Returns nil if Accessibility is not granted or the
    /// attribute is not present.
    private func documentURLviaAX(pid: pid_t) -> String? {
        guard ContextService.hasAccessibilityPermission else { return nil }

        let app = AXUIElementCreateApplication(pid)

        // Try the main window first, then fall back to the focused window
        for windowAttr in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            var winRef: AnyObject?
            guard AXUIElementCopyAttributeValue(app, windowAttr as CFString, &winRef) == .success,
                  CFGetTypeID(winRef as CFTypeRef) == AXUIElementGetTypeID()
            else { continue }

            let window = winRef as! AXUIElement

            // kAXDocument holds the URL of the document loaded in the window
            var docRef: AnyObject?
            if AXUIElementCopyAttributeValue(window, "AXDocument" as CFString, &docRef) == .success,
               let docStr = docRef as? String, !docStr.isEmpty {
                return docStr
            }
        }
        return nil
    }

    // MARK: - AX helpers

    private func axStringAttribute(_ element: AXUIElement, _ attr: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private func axElement(_ parent: AXUIElement, _ attr: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(parent, attr as CFString, &value) == .success,
              let ref = value
        else { return nil }
        guard CFGetTypeID(ref as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    private func collectText(from root: AXUIElement, limit: Int) -> String {
        var collected = ""
        var queue: [AXUIElement] = [root]
        while !queue.isEmpty && collected.count < limit {
            let el = queue.removeFirst()
            if let text = axStringAttribute(el, kAXValueAttribute as String),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                collected += text + " "
            }
            var childrenRef: AnyObject?
            if AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childrenRef) == .success,
               let children = childrenRef as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return String(collected.prefix(limit))
    }

    private func surroundingContext(in text: String, around target: String, radius: Int) -> String {
        guard !target.isEmpty,
              let range = text.range(of: target, options: .caseInsensitive)
        else { return String(text.prefix(radius * 2)) }
        let lower = text.index(range.lowerBound, offsetBy: -radius,
                               limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: radius,
                               limitedBy: text.endIndex)   ?? text.endIndex
        return String(text[lower..<upper])
    }

    // MARK: - AppleScript runner

    private func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }
}

typealias BrowserService = ContextService
