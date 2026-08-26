import Foundation

/// Normalize raw text before TTS and split it into generation-safe chunks.
enum TextPreprocessor {
    static let maxChunkChars = 400

    /// Normalize raw text before TTS — strips markup/noise and preserves paragraph pauses.
    static func preprocessText(_ text: String) -> String {
        var s = text

        func re(_ pattern: String, _ replacement: String, options: NSRegularExpression.Options = []) {
            guard let rx = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let full = NSRange(s.startIndex..., in: s)
            s = rx.stringByReplacingMatches(in: s, range: full, withTemplate: replacement)
        }

        let rawLines = s.components(separatedBy: "\n")
        var normalizedLines: [String] = []
        for (index, line) in rawLines.enumerated() {
            normalizedLines.append(line)
            guard index < rawLines.count - 1 else { continue }
            let current = line.trimmingCharacters(in: .whitespaces)
            let next = rawLines[index + 1].trimmingCharacters(in: .whitespaces)
            if !current.isEmpty && !next.isEmpty {
                normalizedLines.append("")
            }
        }
        s = normalizedLines.joined(separator: "\n")

        // Markdown and common rich-text leftovers.
        re("```[\\s\\S]*?```", " ", options: .dotMatchesLineSeparators)
        re("~~~[\\s\\S]*?~~~", " ", options: .dotMatchesLineSeparators)
        re("`([^`\\n]+)`", "$1")
        re("!\\[[^\\]]*\\]\\([^)]*\\)", "")
        re("\\[([^\\]]+)\\]\\([^)]*\\)", "$1")
        re("^#{1,6}\\s+", "", options: .anchorsMatchLines)
        re("\\*{3}([^*\\n]+)\\*{3}", "$1")
        re("_{3}([^_\\n]+)_{3}", "$1")
        re("\\*{2}([^*\\n]+)\\*{2}", "$1")
        re("_{2}([^_\\n]+)_{2}", "$1")
        re("\\*([^*\\n]+)\\*", "$1")
        re("_([^_\\n]+)_", "$1")
        re("~~([^~\\n]+)~~", "$1")
        re("^[-*_=]{3,}\\s*$", "", options: .anchorsMatchLines)
        re("^>+\\s*", "", options: .anchorsMatchLines)
        re("^[|\\-:\\s]+$", "", options: .anchorsMatchLines)
        re("\\|", " ")
        re("^[\\-\\*\\+]\\s+", "", options: .anchorsMatchLines)
        re("^\\d+[.)\\s]\\s*", "", options: .anchorsMatchLines)

        s = s.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return "" }
            guard let last = trimmed.last else { return trimmed }
            if ".!?".contains(last) {
                return trimmed
            }
            if ",:;".contains(last) {
                return String(trimmed.dropLast()) + "."
            }
            return trimmed + "."
        }.joined(separator: "\n")

        // Slack timestamps: [9:19 AM]
        re(#"\[\d{1,2}:\d{2}\s*(AM|PM)\]"#, "")
        // Slack emoji codes: :thankyoured:
        re(#":\w[\w+\-]*:"#, "")
        // File attachment lines: "Binary splunkd.log", "Zip JAMF…", "Image …", "Screenshot …"
        re(#"^(Binary|Zip|Image|PDF|File|Screenshot)\s+\S+.*$"#, "", options: .anchorsMatchLines)
        // URLs
        re(#"https?://\S+"#, "link")
        re(#"\b\w+\.\w{2,4}/\S*"#, "link")
        // Collapse multiple blank lines
        re(#"\n{3,}"#, "\n\n")

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split cleaned text into TTS-safe chunks without crossing paragraph boundaries.
    static func splitIntoSentences(_ text: String) -> [String] {
        let cleaned = preprocessText(text)
        guard !cleaned.isEmpty else { return [] }

        let paragraphs = cleaned.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs.flatMap { splitParagraph($0) }
    }

    /// Split one paragraph on sentence boundaries, capped for Kokoro's token limit.
    static func splitParagraph(_ text: String) -> [String] {
        let maxChunkChars = Self.maxChunkChars

        // Use NSLinguisticTagger for sentence boundary detection — handles
        // abbreviations, "Mr.", decimals, and URLs far better than naive punctuation split.
        var chunks: [String] = []
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = text

        var sentences: [String] = []
        let range = NSRange(text.startIndex..., in: text)
        tagger.enumerateTags(in: range,
                             unit: .sentence,
                             scheme: .tokenType,
                             options: []) { _, tokenRange, _ in
            if let r = Range(tokenRange, in: text) {
                let s = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { sentences.append(s) }
            }
        }

        // Fallback: if tagger produced nothing (very short text), use the whole thing
        if sentences.isEmpty { return splitByWords(text, maxChars: maxChunkChars) }

        // Merge very short sentences into the previous chunk, split oversized ones
        var current = ""
        for sentence in sentences {
            if sentence.count > maxChunkChars {
                // Long sentence: flush current, then split by clause (,;—)
                if !current.isEmpty { chunks.append(current); current = "" }
                let clauses = sentence.components(separatedBy: CharacterSet(charactersIn: ",;—"))
                var clauseBuffer = ""
                for clause in clauses {
                    let c = clause.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !c.isEmpty else { continue }
                    if c.count > maxChunkChars {
                        if !clauseBuffer.isEmpty { chunks.append(clauseBuffer); clauseBuffer = "" }
                        chunks.append(contentsOf: splitByWords(c, maxChars: maxChunkChars))
                        continue
                    }
                    if clauseBuffer.count + c.count > maxChunkChars {
                        if !clauseBuffer.isEmpty { chunks.append(clauseBuffer) }
                        clauseBuffer = c
                    } else {
                        clauseBuffer = clauseBuffer.isEmpty ? c : clauseBuffer + ", " + c
                    }
                }
                if !clauseBuffer.isEmpty { chunks.append(clauseBuffer) }
            } else if current.count + sentence.count > maxChunkChars {
                if !current.isEmpty { chunks.append(current) }
                current = sentence
            } else {
                current = current.isEmpty ? sentence : current + " " + sentence
            }
        }
        if !current.isEmpty { chunks.append(current) }

        return chunks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func splitByWords(_ text: String, maxChars: Int) -> [String] {
        var chunks: [String] = []
        var current = ""

        for word in text.split(separator: " ") {
            let next = String(word)
            if next.count > maxChars {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                var remainder = next
                while !remainder.isEmpty {
                    let end = remainder.index(remainder.startIndex, offsetBy: min(maxChars, remainder.count))
                    chunks.append(String(remainder[..<end]))
                    remainder = String(remainder[end...])
                }
            } else if current.count + next.count + 1 > maxChars {
                if !current.isEmpty { chunks.append(current) }
                current = next
            } else {
                current = current.isEmpty ? next : current + " " + next
            }
        }

        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
