// AIService.swift — Calls the OpenAI API for context-aware definitions
import Foundation

// Holds information about the browser page that was active during text selection
struct PageInfo {
    var url: String
    var title: String
    var content: String   // ~3 000 chars of text centred around the selected word
    var browser: String
}

class AIService {
    static let shared = AIService()
    private init() {}

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Sends the selected term + article context to OpenAI and returns a definition.
    func define(
        term: String,
        pageInfo: PageInfo?,
        apiKey: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")

        // Require real page content — never give a generic definition without context
        let pageContent = pageInfo?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pageContent.isEmpty else {
            let msg = """
            ⚠️  Couldn't read the page content this time.

            If a permission dialog just appeared and you clicked Allow — \
            please try again. The first request always fails while macOS \
            processes the new permission; the second one will work.

            If no dialog appeared, check these once:
            • Accessibility: System Settings → Privacy & Security → \
            Accessibility → enable Contexto
            • For Chrome/Edge: the page must be publicly accessible \
            (not behind a login wall)
            • For Safari: Safari menu → Develop → Allow JavaScript from Apple Events
            """
            completion(.success(msg))
            return
        }

        let systemPrompt = """
        You explain words and phrases to someone reading a specific article or document. \
        You have been given a text excerpt from exactly what they are reading right now — \
        use it. Write 2-3 short sentences: a clear plain-English definition, then one \
        sentence that explains how this term applies to the specific subject, people, \
        events, or concepts in the excerpt. You must draw your contextual sentence \
        directly from the provided text — never invent an example or use a generic one. \
        Never mention the name of this tool. \
        Write naturally, conversationally, without bullet points or headers.
        """

        var ctx = ""
        if let info = pageInfo {
            if !info.title.isEmpty { ctx += "Document: \(info.title)\n" }
            if !info.url.isEmpty   { ctx += "URL: \(info.url)\n" }
        }
        ctx += "\nText excerpt (centred around the selected word):\n\(String(pageContent.prefix(3500)))"
        ctx += "\n\nWord or phrase to explain: \"\(term)\""
        let userMsg = ctx

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "max_tokens": 400,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMsg]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(makeError("Failed to encode request body")))
            return
        }
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { responseData, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let responseData = responseData else {
                completion(.failure(self.makeError("Empty response from API")))
                return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
                else { throw self.makeError("Unexpected JSON structure") }

                // Success path — OpenAI returns choices[0].message.content
                if let choices = json["choices"] as? [[String: Any]],
                   let first   = choices.first,
                   let message = first["message"] as? [String: Any],
                   let text    = message["content"] as? String {
                    completion(.success(text))
                    return
                }

                // Error path
                if let errObj = json["error"] as? [String: Any],
                   let msg    = errObj["message"] as? String {
                    throw self.makeError(msg)
                }

                throw self.makeError("Unrecognised API response")

            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "AIService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
