import AVFoundation
import Combine
import MLX
import MLXLMCommon
import MLXAudioTTS
import MLXAudioCore
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "SpeechEngine")

struct VoicePreset: Identifiable, Hashable {
    let name: String
    let kokoroVoice: String

    var id: String { kokoroVoice }

    static let defaultPreset = VoicePreset(
        name: "Heart",
        kokoroVoice: "af_heart"
    )
}

private enum EspeakTextProcessorError: LocalizedError {
    case missingExecutable
    case failed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            return "espeak-ng was not found."
        case let .failed(status, stderr):
            if stderr.isEmpty {
                return "espeak-ng exited with status \(status)."
            }
            return "espeak-ng exited with status \(status): \(stderr)"
        }
    }
}

/// espeak-ng based text processor for converting plain text to IPA phonemes.
struct EspeakTextProcessor: TextProcessor {
    private static let executablePaths = [
        "/opt/homebrew/bin/espeak-ng",
        "/usr/local/bin/espeak-ng",
        "/usr/bin/espeak-ng",
    ]

    static var installedExecutablePath: String? {
        if let bundled = bundledExecutableURL,
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled.path
        }
        return executablePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isUsingBundledRuntime: Bool {
        guard let bundledPath = bundledExecutableURL?.path,
              installedExecutablePath == bundledPath,
              bundledDataParentURL != nil else {
            return false
        }
        return true
    }

    private static var bundledExecutableURL: URL? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("espeak-ng")
    }

    private static var bundledDataParentURL: URL? {
        guard let dataURL = Bundle.main.resourceURL?.appendingPathComponent("espeak-ng-data"),
              FileManager.default.fileExists(atPath: dataURL.path) else {
            return nil
        }
        return dataURL.deletingLastPathComponent()
    }

    func process(text: String, language: String?) throws -> String {
        let process = Process()
        guard let executablePath = Self.installedExecutablePath else {
            throw EspeakTextProcessorError.missingExecutable
        }

        process.executableURL = URL(fileURLWithPath: executablePath)
        var arguments = ["--ipa", "-q"]
        if executablePath == Self.bundledExecutableURL?.path,
           let dataParentURL = Self.bundledDataParentURL {
            arguments.append("--path=\(dataParentURL.path)")
        }
        arguments.append(text)
        process.arguments = arguments

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw EspeakTextProcessorError.failed(status: process.terminationStatus, stderr: stderr)
        }

        let ipa = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // espeak-ng outputs multiple lines for multi-sentence input — join them
        return ipa.replacingOccurrences(of: "\n", with: " ")
    }
}

/// Text-to-speech engine powered by Kokoro 82M via mlx-audio-swift.
/// Non-autoregressive: generates entire audio in one forward pass.
@MainActor
class SpeechEngine: NSObject, ObservableObject {
    static let shared = SpeechEngine()

    enum State { case idle, playing, paused, loading, generating }

    enum ModelStatus: Equatable {
        case notLoaded
        case downloading(progress: Double)
        case loading
        case ready
        case error(String)
    }

    @Published var state: State = .idle
    @Published var modelStatus: ModelStatus = .notLoaded
    @Published var currentText: String = ""
    @Published var progress: Double = 0
    @Published var speed: Double = {
        let saved = UserDefaults.standard.double(forKey: "playbackSpeed")
        guard saved >= 0.5, saved <= 2.0 else { return 1.0 }
        return saved
    }() {
        didSet {
            UserDefaults.standard.set(speed, forKey: "playbackSpeed")
        }
    }
    @Published var previewingVoice: String?
    @Published var selectedVoice: String = UserDefaults.standard.string(forKey: "selectedVoice")
        ?? VoicePreset.defaultPreset.kokoroVoice {
        didSet {
            log.info("Voice changed to: \(self.selectedVoice)")
            UserDefaults.standard.set(selectedVoice, forKey: "selectedVoice")
            guard state == .playing || state == .paused || state == .generating else { return }
            let textToRepeat = currentText.isEmpty ? ReadingQueue.shared.currentItem?.text : currentText
            if let text = textToRepeat {
                speak(text)
            }
        }
    }

    static let voicePresets: [VoicePreset] = [
        VoicePreset(name: "Heart", kokoroVoice: "af_heart"),
        VoicePreset(name: "Bella", kokoroVoice: "af_bella"),
        VoicePreset(name: "Sky", kokoroVoice: "af_sky"),
        VoicePreset(name: "Nicole", kokoroVoice: "af_nicole"),
        VoicePreset(name: "Sarah", kokoroVoice: "af_sarah"),
        VoicePreset(name: "Nova", kokoroVoice: "af_nova"),
        VoicePreset(name: "River", kokoroVoice: "af_river"),
        VoicePreset(name: "Adam", kokoroVoice: "am_adam"),
        VoicePreset(name: "Michael", kokoroVoice: "am_michael"),
        VoicePreset(name: "Eric", kokoroVoice: "am_eric"),
        VoicePreset(name: "Liam", kokoroVoice: "am_liam"),
        VoicePreset(name: "Alice (British)", kokoroVoice: "bf_alice"),
        VoicePreset(name: "Daniel (British)", kokoroVoice: "bm_daniel"),
    ]

    private var model: (any SpeechGenerationModel)?
    private var generationTask: Task<Void, Never>?

    // Generation ID: incremented on each speak() call so stale callbacks are ignored
    private var generationID: UInt64 = 0

    // Audio playback via AVAudioEngine
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var audioFormat: AVAudioFormat?
    private var totalSamplesScheduled = 0
    private var playbackChunksScheduled = 0
    private var playbackChunksCompleted = 0
    private var streamingGenerationComplete = false
    private var streamingPlaybackStarted = false
    private var progressTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewAudioEngine: AVAudioEngine?
    private var previewPlayerNode: AVAudioPlayerNode?

    private static let modelID = "mlx-community/Kokoro-82M-bf16"
    private static let sampleRate: Double = 24000
    private static let fastEnoughMargin = 1.15
    private static let minimumStartupBufferSeconds = 1.25
    private static let comfortableStartupBufferSeconds = 3.0
    private static let lowWaterWallSeconds = 2.5

    override init() {
        super.init()
    }

    // MARK: - Model Loading

    /// Returns true if the Kokoro model is already present in the local HuggingFace cache.
    private func isModelCached() -> Bool {
        // Mirrors ModelUtils.resolveOrDownloadModel path logic:
        // <HubCache.default.cacheDirectory>/mlx-audio/mlx-community_Kokoro-82M-bf16/
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .deletingLastPathComponent()
            .appendingPathComponent(".cache/huggingface/hub")
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache/huggingface/hub")
        let modelDir = cacheDir
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(Self.modelID.replacingOccurrences(of: "/", with: "_"))
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: modelDir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return false }
        return files.contains {
            guard $0.pathExtension == "safetensors" else { return false }
            let size = (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size > 0
        }
    }

    func loadModel() async {
        guard modelStatus == .notLoaded || isErrorStatus else {
            log.info("loadModel() skipped — modelStatus=\(String(describing: self.modelStatus))")
            return
        }
        log.info("loadModel() starting...")
        if isModelCached() {
            modelStatus = .loading
            log.info("Model found in cache — loading weights")
        } else {
            modelStatus = .downloading(progress: 0.0)
            log.info("Model not in cache — downloading from HuggingFace")
        }

        do {
            let textProcessor = EspeakTextProcessor()
            let loaded = try await KokoroModel.fromPretrained(
                Self.modelID,
                textProcessor: textProcessor
            )
            self.model = loaded
            modelStatus = .ready
            log.info("Kokoro model loaded successfully")
            if state == .idle, let item = ReadingQueue.shared.currentItem {
                speak(item.text)
            }
        } catch {
            log.error("Model load failed: \(error.localizedDescription)")
            modelStatus = .error(error.localizedDescription)
        }
    }

    private var isErrorStatus: Bool {
        if case .error = modelStatus { return true }
        return false
    }

    // MARK: - Voice Preview

    func previewVoice(_ preset: VoicePreset) {
        if previewingVoice == preset.kokoroVoice {
            stopVoicePreview()
            return
        }

        guard modelStatus == .ready, let model else {
            log.warning("previewVoice() called but model not ready")
            return
        }

        stopVoicePreview()
        previewingVoice = preset.kokoroVoice

        previewTask = Task {
            do {
                let params = GenerateParameters()
                let sampleText = "Hello from \(preset.name), Recite can read articles, emails, and notes out loud"
                let audio = try await model.generate(
                    text: sampleText,
                    voice: preset.kokoroVoice,
                    refAudio: nil,
                    refText: nil,
                    language: "en-us",
                    generationParameters: params
                )
                if Task.isCancelled { return }
                let samples = audio.asArray(Float.self)
                await MainActor.run {
                    guard self.previewingVoice == preset.kokoroVoice else { return }
                    self.playVoicePreview(samples, voiceID: preset.kokoroVoice)
                }
            } catch {
                log.error("Voice preview failed: \(error.localizedDescription)")
                await MainActor.run {
                    guard self.previewingVoice == preset.kokoroVoice else { return }
                    self.stopVoicePreview()
                }
            }
        }
    }

    func stopVoicePreview() {
        previewTask?.cancel()
        previewTask = nil
        previewPlayerNode?.stop()
        previewAudioEngine?.stop()
        previewPlayerNode = nil
        previewAudioEngine = nil
        previewingVoice = nil
    }

    private func playVoicePreview(_ samples: [Float], voiceID: String) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            stopVoicePreview()
            return
        }
        buffer.frameLength = frameCount
        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = max(-1.0, min(1.0, samples[i]))
        }

        do {
            try engine.start()
            previewAudioEngine = engine
            previewPlayerNode = player
            player.scheduleBuffer(buffer) { [weak self] in
                Task { @MainActor in
                    guard let self, self.previewingVoice == voiceID else { return }
                    self.stopVoicePreview()
                }
            }
            player.play()
            log.info("Voice preview started for \(voiceID)")
        } catch {
            log.error("Voice preview audio failed: \(error.localizedDescription)")
            stopVoicePreview()
        }
    }

    // MARK: - Playback

    func speak(_ text: String) {
        guard modelStatus == .ready, let model = model else {
            log.warning("speak() called but model not ready (modelStatus=\(String(describing: self.modelStatus)))")
            return
        }

        log.info("speak() called with \(text.count) chars")

        // Cancel any in-progress generation
        stopVoicePreview()
        generationTask?.cancel()
        stopAudioEngine()

        currentText = text
        progress = 0
        state = .generating

        // Increment generation ID so stale callbacks from previous speak() are ignored
        generationID &+= 1
        let myGenID = generationID
        log.info("Starting generation #\(myGenID)")

        generationTask = Task {
            do {
                // Split long text into sentences for incremental generation
                let sentences = splitIntoSentences(text)
                log.info("Split into \(sentences.count) sentences")

                guard !sentences.isEmpty else {
                    await MainActor.run {
                        guard self.generationID == myGenID else { return }
                        self.state = .idle
                        self.currentText = ""
                        self.progress = 0
                    }
                    return
                }

                let generationStartTime = CFAbsoluteTimeGetCurrent()
                let totalTextChars = sentences.reduce(0) { $0 + $1.count }
                var generatedAudioSeconds = 0.0
                var generatedTextChars = 0
                var playbackHasStarted = false
                var audioEngineReady = true
                await MainActor.run {
                    guard self.generationID == myGenID else { return }
                    audioEngineReady = self.setupAudioEngine()
                    self.startProgressTracker(totalEstimatedAudioSeconds: {
                        let textRatio = totalTextChars > 0
                            ? Double(generatedTextChars) / Double(totalTextChars)
                            : 1.0
                        guard textRatio > 0 else { return generatedAudioSeconds }
                        return max(generatedAudioSeconds / textRatio, generatedAudioSeconds)
                    })
                }
                guard audioEngineReady else {
                    await MainActor.run {
                        guard self.generationID == myGenID else { return }
                        self.state = .idle
                        self.progress = 0
                    }
                    return
                }

                for (i, sentence) in sentences.enumerated() {
                    if Task.isCancelled { return }

                    let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    log.info("Generating sentence \(i+1)/\(sentences.count) (\(trimmed.count) chars)")

                    let params = GenerateParameters()
                    let audio = try await model.generate(
                        text: trimmed,
                        voice: self.selectedVoice,
                        refAudio: nil,
                        refText: nil,
                        language: "en-us",
                        generationParameters: params
                    )

                    let samples = audio.asArray(Float.self)
                    let chunkAudioSeconds = Double(samples.count) / Self.sampleRate
                    generatedAudioSeconds += chunkAudioSeconds
                    generatedTextChars += trimmed.count

                    let elapsed = max(CFAbsoluteTimeGetCurrent() - generationStartTime, 0.001)
                    let generationRate = generatedAudioSeconds / elapsed
                    let estimatedTotalAudioSeconds = estimateTotalAudioSeconds(
                        generatedAudioSeconds: generatedAudioSeconds,
                        generatedTextChars: generatedTextChars,
                        totalTextChars: totalTextChars
                    )
                    let estimatedRemainingAudioSeconds = max(estimatedTotalAudioSeconds - generatedAudioSeconds, 0)
                    let startupTarget = startupBufferTargetSeconds(
                        generationRate: generationRate,
                        playbackRate: self.speed,
                        estimatedRemainingAudioSeconds: estimatedRemainingAudioSeconds
                    )
                    let shouldStartPlayback = generatedAudioSeconds >= startupTarget || i == sentences.count - 1

                    log.info("Sentence \(i+1, privacy: .public): \(samples.count, privacy: .public) samples (\(String(format: "%.2f", chunkAudioSeconds), privacy: .public)s), generation \(String(format: "%.2f", generationRate), privacy: .public)x audio-time, startup target \(String(format: "%.2f", startupTarget), privacy: .public)s")

                    await MainActor.run {
                        guard self.generationID == myGenID else { return }
                        self.scheduleStreamingAudio(samples, isFinalChunk: false)
                        self.progress = min(Double(i + 1) / Double(sentences.count), 0.98)

                        guard shouldStartPlayback, !playbackHasStarted else { return }
                        playbackHasStarted = true
                        self.streamingPlaybackStarted = true
                        self.playerNode?.play()
                        self.state = .playing
                        log.info("Streaming playback started after buffering \(String(format: "%.2f", generatedAudioSeconds), privacy: .public)s audio; generation rate \(String(format: "%.2f", generationRate), privacy: .public)x, playback rate \(String(format: "%.2f", self.speed), privacy: .public)x")
                    }
                }

                if Task.isCancelled { return }

                await MainActor.run {
                    guard self.generationID == myGenID else { return }
                    self.streamingGenerationComplete = true
                    if !playbackHasStarted {
                        playbackHasStarted = true
                        self.streamingPlaybackStarted = true
                        self.playerNode?.play()
                        self.state = .playing
                    }
                    self.finishPlaybackIfComplete()
                }

            } catch {
                log.error("Generation error: \(error.localizedDescription)")
                if !Task.isCancelled {
                    await MainActor.run {
                        guard self.generationID == myGenID else { return }
                        state = .idle
                        currentText = ""
                        progress = 0
                    }
                }
            }
        }
    }

    private func estimateTotalAudioSeconds(
        generatedAudioSeconds: Double,
        generatedTextChars: Int,
        totalTextChars: Int
    ) -> Double {
        guard generatedAudioSeconds > 0, generatedTextChars > 0, totalTextChars > 0 else {
            return generatedAudioSeconds
        }
        let audioSecondsPerChar = generatedAudioSeconds / Double(generatedTextChars)
        return audioSecondsPerChar * Double(totalTextChars)
    }

    /// Pick the startup buffer that avoids underruns.
    /// If generation is faster than playback, start quickly. If it is slower, wait
    /// long enough that the estimated buffer drain is covered before playback begins.
    private func startupBufferTargetSeconds(
        generationRate: Double,
        playbackRate: Double,
        estimatedRemainingAudioSeconds: Double
    ) -> Double {
        let playbackRate = max(playbackRate, 0.1)
        let lowWaterAudioSeconds = Self.lowWaterWallSeconds * playbackRate
        guard generationRate > 0 else {
            return max(lowWaterAudioSeconds, Self.comfortableStartupBufferSeconds)
        }

        if generationRate >= playbackRate * Self.fastEnoughMargin {
            return Self.minimumStartupBufferSeconds * playbackRate
        }

        if generationRate >= playbackRate {
            return max(lowWaterAudioSeconds, Self.comfortableStartupBufferSeconds * playbackRate)
        }

        let expectedDrain = ((playbackRate - generationRate) / generationRate) * estimatedRemainingAudioSeconds
        return max(lowWaterAudioSeconds + expectedDrain, Self.comfortableStartupBufferSeconds * playbackRate)
    }

    /// Normalize raw text before TTS — strips markup/noise and preserves paragraph pauses.
    private func preprocessText(_ text: String) -> String {
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
    private func splitIntoSentences(_ text: String) -> [String] {
        let cleaned = preprocessText(text)
        guard !cleaned.isEmpty else { return [] }

        let paragraphs = cleaned.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs.flatMap { splitParagraph($0) }
    }

    /// Split one paragraph on sentence boundaries, capped for Kokoro's token limit.
    private func splitParagraph(_ text: String) -> [String] {
        let maxChunkChars = 400

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

    private func splitByWords(_ text: String, maxChars: Int) -> [String] {
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

    private func scheduleStreamingAudio(_ samples: [Float], isFinalChunk: Bool) {
        guard let player = playerNode, let format = audioFormat else { return }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            state = .idle
            progress = 0
            return
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            state = .idle
            progress = 0
            return
        }
        for i in 0..<samples.count {
            channelData[i] = max(-1.0, min(1.0, samples[i]))
        }

        totalSamplesScheduled += samples.count
        playbackChunksScheduled += 1
        let expectedGenID = self.generationID

        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.generationID == expectedGenID else { return }
                self.playbackChunksCompleted += 1
                if !self.streamingGenerationComplete,
                   self.streamingPlaybackStarted,
                   self.playbackChunksCompleted >= self.playbackChunksScheduled {
                    self.state = .generating
                    log.info("Playback buffer drained before generation finished; waiting for the next chunk")
                }
                self.finishPlaybackIfComplete()
            }
        }
        streamingGenerationComplete = streamingGenerationComplete || isFinalChunk
        if streamingPlaybackStarted,
           state != .paused,
           !player.isPlaying,
           bufferedAudioSeconds() >= resumeBufferTargetSeconds() {
            player.play()
            state = .playing
            log.info("Playback resumed with \(String(format: "%.2f", self.bufferedAudioSeconds()), privacy: .public)s buffered")
        }
        log.info("Scheduled streaming chunk \(self.playbackChunksScheduled, privacy: .public): \(String(format: "%.2f", Double(samples.count) / Self.sampleRate), privacy: .public)s audio")
    }

    private func setupAudioEngine() -> Bool {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = Float(speed)
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!

        engine.attach(player)
        engine.attach(timePitch)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            self.audioEngine = engine
            self.playerNode = player
            self.timePitchNode = timePitch
            self.audioFormat = format
            self.totalSamplesScheduled = 0
            self.playbackChunksScheduled = 0
            self.playbackChunksCompleted = 0
            self.streamingGenerationComplete = false
            self.streamingPlaybackStarted = false
            log.info("Audio engine started (speed: \(self.speed)x)")
            return true
        } catch {
            log.error("Failed to start audio engine: \(error.localizedDescription)")
            return false
        }
    }

    private func startProgressTracker(totalEstimatedAudioSeconds: @escaping @MainActor () -> Double) {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled && (state == .generating || state == .playing || state == .paused) {
                let playedSeconds = currentPlaybackSourceSeconds()
                let totalSeconds = max(totalEstimatedAudioSeconds(), Double(totalSamplesScheduled) / Self.sampleRate)
                if totalSeconds > 0 {
                    progress = min(playedSeconds / totalSeconds, 0.99)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func currentPlaybackSourceSeconds() -> Double {
        guard let player = playerNode,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return max(Double(playerTime.sampleTime) / Self.sampleRate, 0)
    }

    private func bufferedAudioSeconds() -> Double {
        max(Double(totalSamplesScheduled) / Self.sampleRate - currentPlaybackSourceSeconds(), 0)
    }

    private func resumeBufferTargetSeconds() -> Double {
        max(Self.minimumStartupBufferSeconds * speed, 0.5)
    }

    private func finishPlaybackIfComplete() {
        guard streamingGenerationComplete,
              playbackChunksScheduled > 0,
              playbackChunksCompleted >= playbackChunksScheduled else {
            return
        }
        finishPlayback()
    }

    private func finishPlayback() {
        progressTask?.cancel()
        progressTask = nil
        progress = 1.0
        state = .idle
        currentText = ""
        stopAudioEngine()
        ReadingQueue.shared.didFinishCurrent()
    }

    private func stopAudioEngine() {
        progressTask?.cancel()
        progressTask = nil
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        timePitchNode = nil
        audioFormat = nil
        totalSamplesScheduled = 0
        playbackChunksScheduled = 0
        playbackChunksCompleted = 0
        streamingGenerationComplete = false
        streamingPlaybackStarted = false
    }

    func pause() {
        guard state == .playing, let player = playerNode else { return }
        player.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused, let player = playerNode else { return }
        player.play()
        state = .playing
    }

    func stop() {
        stopVoicePreview()
        generationID &+= 1
        generationTask?.cancel()
        stopAudioEngine()
        state = .idle
        currentText = ""
        progress = 0
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused:  resume()
        case .idle:    ReadingQueue.shared.playNext()
        case .loading, .generating: break
        }
    }

    func playNext() {
        stop()
        ReadingQueue.shared.playNext()
    }

    func updateSpeed(_ newSpeed: Double) {
        let clampedSpeed = min(max(newSpeed, 0.5), 2.0)
        speed = clampedSpeed
        timePitchNode?.rate = Float(clampedSpeed)
        log.info("Speed updated to \(clampedSpeed)x")
    }
}
