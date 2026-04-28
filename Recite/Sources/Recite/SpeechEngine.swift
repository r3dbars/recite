import AVFoundation
import Combine
import MLX
import MLXLMCommon
import MLXAudioTTS
import MLXAudioCore
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "SpeechEngine")

struct VoicePreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let kokoroVoice: String

    static let defaultPreset = VoicePreset(
        name: "Heart",
        kokoroVoice: "af_heart"
    )
}

/// espeak-ng based text processor for converting plain text to IPA phonemes.
struct EspeakTextProcessor: TextProcessor {
    func process(text: String, language: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/espeak-ng")
        process.arguments = ["--ipa", "-q", text]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
    @Published var speed: Double = 1.0  // 0.5x – 2.0x playback speed
    @Published var selectedVoice: String = UserDefaults.standard.string(forKey: "selectedVoice")
        ?? VoicePreset.defaultPreset.kokoroVoice {
        didSet {
            log.info("Voice changed to: \(self.selectedVoice)")
            UserDefaults.standard.set(selectedVoice, forKey: "selectedVoice")
            // Re-speak current text with new voice
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

    private static let modelID = "mlx-community/Kokoro-82M-bf16"
    private static let sampleRate: Double = 24000

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
        } catch {
            log.error("Model load failed: \(error.localizedDescription)")
            modelStatus = .error(error.localizedDescription)
        }
    }

    private var isErrorStatus: Bool {
        if case .error = modelStatus { return true }
        return false
    }

    // MARK: - Playback

    func speak(_ text: String) {
        guard modelStatus == .ready, let model = model else {
            log.warning("speak() called but model not ready (modelStatus=\(String(describing: self.modelStatus)))")
            return
        }

        log.info("speak() called with \(text.count) chars")

        // Cancel any in-progress generation
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

                var allSamples: [Float] = []
                let startTime = CFAbsoluteTimeGetCurrent()

                for (i, sentence) in sentences.enumerated() {
                    if Task.isCancelled { return }

                    let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }

                    log.info("Generating sentence \(i+1)/\(sentences.count): \(String(trimmed.prefix(50)))...")

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
                    log.info("Sentence \(i+1): \(samples.count) samples (\(Double(samples.count) / Self.sampleRate)s)")
                    allSamples.append(contentsOf: samples)

                    await MainActor.run {
                        guard self.generationID == myGenID else { return }
                        self.progress = Double(i + 1) / Double(sentences.count) * 0.5
                    }
                }

                if Task.isCancelled { return }

                let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                let audioDuration = Double(allSamples.count) / Self.sampleRate
                let rtf = audioDuration / elapsed
                log.info("Generation complete: \(allSamples.count) samples, \(String(format: "%.1f", audioDuration))s audio in \(String(format: "%.1f", elapsed))s (\(String(format: "%.1f", rtf))x real-time)")

                await MainActor.run {
                    guard self.generationID == myGenID else { return }
                    self.playAudio(allSamples)
                }

            } catch {
                log.error("Generation error: \(error.localizedDescription)")
                if !Task.isCancelled {
                    await MainActor.run {
                        guard self.generationID == myGenID else { return }
                        state = .idle
                        currentText = ""
                    }
                }
            }
        }
    }

    /// Clean raw text before TTS — strips Slack noise, timestamps, emoji codes, file attachments.
    private func preprocessText(_ text: String) -> String {
        var s = text

        func re(_ pattern: String, _ replacement: String, multiline: Bool = false) {
            var opts: NSRegularExpression.Options = []
            if multiline { opts.insert(.anchorsMatchLines) }
            guard let rx = try? NSRegularExpression(pattern: pattern, options: opts) else { return }
            let full = NSRange(s.startIndex..., in: s)
            s = rx.stringByReplacingMatches(in: s, range: full, withTemplate: replacement)
        }

        // Slack timestamps: [9:19 AM]
        re(#"\[\d{1,2}:\d{2}\s*(AM|PM)\]"#, "")
        // Slack emoji codes: :thankyoured:
        re(#":\w[\w+\-]*:"#, "")
        // File attachment lines: "Binary splunkd.log", "Zip JAMF…", "Image …", "Screenshot …"
        re(#"^(Binary|Zip|Image|PDF|File|Screenshot)\s+\S+.*$"#, "", multiline: true)
        // URLs
        re(#"https?://\S+"#, "link")
        re(#"\b\w+\.\w{2,4}/\S*"#, "link")
        // Collapse multiple blank lines
        re(#"\n{3,}"#, "\n\n")

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split cleaned text into TTS-safe chunks.
    /// Rules: split on sentence boundaries, but avoid splitting on abbreviations,
    /// timestamps, decimals, or mid-word periods. Chunks are capped at ~400 chars
    /// to stay well within Kokoro's 510-token limit.
    private func splitIntoSentences(_ text: String) -> [String] {
        let cleaned = preprocessText(text)
        let maxChunkChars = 400

        // Use NSLinguisticTagger for sentence boundary detection — handles
        // abbreviations, "Mr.", decimals, and URLs far better than naive punctuation split.
        var chunks: [String] = []
        let tagger = NSLinguisticTagger(tagSchemes: [.tokenType], options: 0)
        tagger.string = cleaned

        var sentences: [String] = []
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        tagger.enumerateTags(in: range,
                             unit: .sentence,
                             scheme: .tokenType,
                             options: []) { _, tokenRange, _ in
            if let r = Range(tokenRange, in: cleaned) {
                let s = String(cleaned[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { sentences.append(s) }
            }
        }

        // Fallback: if tagger produced nothing (very short text), use the whole thing
        if sentences.isEmpty { return [cleaned] }

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

    private func playAudio(_ samples: [Float]) {
        setupAudioEngine()
        guard let player = playerNode, let format = audioFormat else { return }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = max(-1.0, min(1.0, samples[i]))
        }

        totalSamplesScheduled = samples.count
        let expectedGenID = self.generationID

        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.generationID == expectedGenID else { return }
                self.finishPlayback()
            }
        }

        player.play()
        state = .playing
        log.info("Playback started (\(samples.count) samples, \(String(format: "%.1f", Double(samples.count) / Self.sampleRate))s)")

        // Track progress
        Task {
            while state == .playing || state == .paused {
                if let player = playerNode, let nodeTime = player.lastRenderTime,
                   let playerTime = player.playerTime(forNodeTime: nodeTime),
                   totalSamplesScheduled > 0 {
                    let currentSample = Double(playerTime.sampleTime)
                    let total = Double(totalSamplesScheduled)
                    // Map playback progress to 0.5–1.0 (first 0.5 was generation)
                    progress = 0.5 + min(currentSample / total, 1.0) * 0.5
                }
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
        }
    }

    private func setupAudioEngine() {
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
            log.info("Audio engine started (speed: \(self.speed)x)")
        } catch {
            log.error("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    private func finishPlayback() {
        progress = 1.0
        state = .idle
        currentText = ""
        stopAudioEngine()
        ReadingQueue.shared.didFinishCurrent()
    }

    private func stopAudioEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        timePitchNode = nil
        audioFormat = nil
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
        speed = newSpeed
        timePitchNode?.rate = Float(newSpeed)
        log.info("Speed updated to \(newSpeed)x")
    }
}
