import AVFoundation
import Combine
import MLX
import MLXLMCommon
import MLXAudioTTS
import MLXAudioCore
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "SpeechEngine")

enum VoiceModelFamily: String, CaseIterable, Identifiable {
    case kokoro
    case qwen
    case chatterbox

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kokoro: return "Kokoro"
        case .qwen: return "Qwen"
        case .chatterbox: return "Chatterbox"
        }
    }

    var detail: String {
        switch self {
        case .kokoro: return "MLX Kokoro 82M"
        case .qwen: return "Qwen voice presets"
        case .chatterbox: return "Chatterbox reference voices"
        }
    }

    var supportsLocalPlayback: Bool {
        self == .kokoro
    }

    var supportsVoiceSamples: Bool {
        true
    }

    var sampleUnavailableReason: String? {
        nil
    }
}

struct VoicePreset: Identifiable, Hashable {
    let name: String
    let voiceID: String
    let modelFamily: VoiceModelFamily
    let detail: String

    var id: String { "\(modelFamily.rawValue):\(voiceID)" }

    var kokoroVoice: String { voiceID }

    var sampleText: String {
        switch modelFamily {
        case .kokoro:
            switch voiceID {
            case "af_heart": return "A calm voice for long articles and notes."
            case "af_bella": return "Soft and clear, with a little warmth."
            case "af_sky": return "Bright, steady, and easy to follow."
            case "af_nicole": return "A gentle voice for focused reading."
            case "af_sarah": return "Clean narration for emails and essays."
            case "af_nova": return "Modern and crisp, good for quick reads."
            case "af_river": return "Relaxed pacing for longer passages."
            case "am_adam": return "A grounded voice for plain spoken text."
            case "am_michael": return "Confident narration with a clear tone."
            case "am_eric": return "Direct and simple, good for short notes."
            case "am_liam": return "Light, natural, and conversational."
            case "bf_alice": return "A British voice for clear narration."
            case "bm_daniel": return "A steady British voice for longer reads."
            default: return "Recite can read selected text aloud on your Mac."
            }
        case .qwen:
            switch voiceID {
            case "Vivian": return "Hello, I am Vivian. This is a quick Recite voice sample."
            case "Serena": return "Hello, I am Serena. This is a quick Recite voice sample."
            case "Uncle_Fu": return "Hello, I am Uncle Fu. This is a quick Recite voice sample."
            case "Dylan": return "Hello, I am Dylan. This is a quick Recite voice sample."
            case "Eric": return "Hello, I am Eric. This is a quick Recite voice sample."
            case "Ryan": return "Hello, I am Ryan. This is a quick Recite voice sample."
            case "Aiden": return "Hello, I am Aiden. This is a quick Recite voice sample."
            case "Ono_Anna": return "Hello, I am Ono Anna. This is a quick Recite voice sample."
            case "Sohee": return "Hello, I am Sohee. This is a quick Recite voice sample."
            default: return "This Qwen voice can be used for local speech."
            }
        case .chatterbox:
            switch voiceID {
            case "default": return "A neutral Chatterbox sample voice."
            case "reference": return "This uses your saved reference voice."
            case "expressive": return "A more animated Chatterbox reading."
            default: return "This Chatterbox voice uses a reference sample."
            }
        }
    }

    var sampleLanguage: String {
        switch modelFamily {
        case .kokoro: return "en-us"
        case .qwen: return "auto"
        case .chatterbox: return "en"
        }
    }

    var sampleVoicePrompt: String {
        switch modelFamily {
        case .kokoro, .qwen: return voiceID
        case .chatterbox: return ""
        }
    }

    var bundledSampleName: String? {
        switch modelFamily {
        case .kokoro:
            return nil
        case .qwen:
            return "qwen_\(voiceID)"
        case .chatterbox:
            return "chatterbox_\(voiceID)"
        }
    }

    static let defaultPreset = VoicePreset(
        name: "Heart",
        voiceID: "af_heart",
        modelFamily: .kokoro,
        detail: "American English · af_heart"
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
    @Published private(set) var selectedVoiceModel: VoiceModelFamily = SpeechEngine.savedVoiceModel()
    @Published private(set) var selectedVoice: String = SpeechEngine.savedVoiceID(for: SpeechEngine.savedVoiceModel())

    static let voicePresets: [VoicePreset] = [
        VoicePreset(name: "Heart", voiceID: "af_heart", modelFamily: .kokoro, detail: "American English · af_heart"),
        VoicePreset(name: "Bella", voiceID: "af_bella", modelFamily: .kokoro, detail: "American English · af_bella"),
        VoicePreset(name: "Sky", voiceID: "af_sky", modelFamily: .kokoro, detail: "American English · af_sky"),
        VoicePreset(name: "Nicole", voiceID: "af_nicole", modelFamily: .kokoro, detail: "American English · af_nicole"),
        VoicePreset(name: "Sarah", voiceID: "af_sarah", modelFamily: .kokoro, detail: "American English · af_sarah"),
        VoicePreset(name: "Nova", voiceID: "af_nova", modelFamily: .kokoro, detail: "American English · af_nova"),
        VoicePreset(name: "River", voiceID: "af_river", modelFamily: .kokoro, detail: "American English · af_river"),
        VoicePreset(name: "Adam", voiceID: "am_adam", modelFamily: .kokoro, detail: "American English · am_adam"),
        VoicePreset(name: "Michael", voiceID: "am_michael", modelFamily: .kokoro, detail: "American English · am_michael"),
        VoicePreset(name: "Eric", voiceID: "am_eric", modelFamily: .kokoro, detail: "American English · am_eric"),
        VoicePreset(name: "Liam", voiceID: "am_liam", modelFamily: .kokoro, detail: "American English · am_liam"),
        VoicePreset(name: "Alice (British)", voiceID: "bf_alice", modelFamily: .kokoro, detail: "British English · bf_alice"),
        VoicePreset(name: "Daniel (British)", voiceID: "bm_daniel", modelFamily: .kokoro, detail: "British English · bm_daniel"),
    ]

    static let qwenVoicePresets: [VoicePreset] = [
        VoicePreset(name: "Vivian", voiceID: "Vivian", modelFamily: .qwen, detail: "Bright young voice"),
        VoicePreset(name: "Serena", voiceID: "Serena", modelFamily: .qwen, detail: "Warm young voice"),
        VoicePreset(name: "Uncle Fu", voiceID: "Uncle_Fu", modelFamily: .qwen, detail: "Low seasoned voice"),
        VoicePreset(name: "Dylan", voiceID: "Dylan", modelFamily: .qwen, detail: "Clear Beijing voice"),
        VoicePreset(name: "Eric", voiceID: "Eric", modelFamily: .qwen, detail: "Lively Chengdu voice"),
        VoicePreset(name: "Ryan", voiceID: "Ryan", modelFamily: .qwen, detail: "Dynamic English voice"),
        VoicePreset(name: "Aiden", voiceID: "Aiden", modelFamily: .qwen, detail: "Sunny American voice"),
        VoicePreset(name: "Ono Anna", voiceID: "Ono_Anna", modelFamily: .qwen, detail: "Playful Japanese voice"),
        VoicePreset(name: "Sohee", voiceID: "Sohee", modelFamily: .qwen, detail: "Warm Korean voice"),
    ]

    static let chatterboxVoicePresets: [VoicePreset] = [
        VoicePreset(name: "Default", voiceID: "default", modelFamily: .chatterbox, detail: "Built-in fallback voice"),
        VoicePreset(name: "Reference Voice", voiceID: "reference", modelFamily: .chatterbox, detail: "Use a saved reference clip"),
        VoicePreset(name: "Expressive", voiceID: "expressive", modelFamily: .chatterbox, detail: "Higher emotion setting"),
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
    private var accumulatedSamples: [Float] = []
    private var seekSampleOffset: Int = 0
    private var playbackID: UInt64 = 0
    private var progressTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewAudioEngine: AVAudioEngine?
    private var previewPlayerNode: AVAudioPlayerNode?
    private var previewFilePlayer: AVAudioPlayer?
    private var previewFileTask: Task<Void, Never>?

    private static let modelID = "mlx-community/Kokoro-82M-bf16"
    private static let sampleRate: Double = 24000
    private static let fastEnoughMargin = 1.15
    private static let minimumStartupBufferSeconds = 1.25
    private static let comfortableStartupBufferSeconds = 3.0
    private static let lowWaterWallSeconds = 2.5
    private static let selectedVoiceModelKey = "selectedVoiceModel"
    private static let legacySelectedVoiceKey = "selectedVoice"

    override init() {
        super.init()
    }

    static func voicePresets(for modelFamily: VoiceModelFamily) -> [VoicePreset] {
        switch modelFamily {
        case .kokoro: return voicePresets
        case .qwen: return qwenVoicePresets
        case .chatterbox: return chatterboxVoicePresets
        }
    }

    func selectVoiceModel(_ modelFamily: VoiceModelFamily) {
        guard selectedVoiceModel != modelFamily else { return }
        stopVoicePreview()
        selectedVoiceModel = modelFamily
        UserDefaults.standard.set(modelFamily.rawValue, forKey: Self.selectedVoiceModelKey)
        selectedVoice = Self.savedVoiceID(for: modelFamily)
        log.info("Voice model changed to: \(modelFamily.rawValue), voice: \(self.selectedVoice)")
        restartPlaybackIfNeeded()
    }

    func selectVoice(_ preset: VoicePreset) {
        if selectedVoiceModel != preset.modelFamily {
            selectedVoiceModel = preset.modelFamily
            UserDefaults.standard.set(preset.modelFamily.rawValue, forKey: Self.selectedVoiceModelKey)
        }

        guard selectedVoice != preset.voiceID else { return }
        stopVoicePreview()
        selectedVoice = preset.voiceID
        persistSelectedVoice()
        log.info("Voice changed to: \(self.selectedVoice)")
        restartPlaybackIfNeeded()
    }

    func canPreview(_ preset: VoicePreset) -> Bool {
        guard preset.modelFamily.supportsVoiceSamples else { return false }
        guard state == .idle else { return false }
        if bundledSampleURL(for: preset) != nil {
            return true
        }
        if preset.modelFamily == .kokoro {
            return modelStatus == .ready
        }
        return false
    }

    private static func savedVoiceModel() -> VoiceModelFamily {
        guard let raw = UserDefaults.standard.string(forKey: selectedVoiceModelKey),
              let modelFamily = VoiceModelFamily(rawValue: raw) else {
            return .kokoro
        }
        return modelFamily
    }

    private static func voiceDefaultsKey(for modelFamily: VoiceModelFamily) -> String {
        "selectedVoice.\(modelFamily.rawValue)"
    }

    private static func savedVoiceID(for modelFamily: VoiceModelFamily) -> String {
        let saved = UserDefaults.standard.string(forKey: voiceDefaultsKey(for: modelFamily))
        let legacySaved = modelFamily == .kokoro
            ? UserDefaults.standard.string(forKey: legacySelectedVoiceKey)
            : nil
        let fallback = voicePresets(for: modelFamily).first?.voiceID ?? VoicePreset.defaultPreset.voiceID
        let candidate = saved ?? legacySaved ?? fallback
        guard voicePresets(for: modelFamily).contains(where: { $0.voiceID == candidate }) else {
            return fallback
        }
        return candidate
    }

    private func persistSelectedVoice() {
        UserDefaults.standard.set(selectedVoice, forKey: Self.voiceDefaultsKey(for: selectedVoiceModel))
        if selectedVoiceModel == .kokoro {
            UserDefaults.standard.set(selectedVoice, forKey: Self.legacySelectedVoiceKey)
        }
    }

    private func restartPlaybackIfNeeded() {
        guard state == .playing || state == .paused || state == .generating else { return }
        guard selectedVoiceModel == .kokoro else { return }
        let textToRepeat = currentText.isEmpty ? ReadingQueue.shared.currentItem?.text : currentText
        if let text = textToRepeat {
            speak(text)
        }
    }

    private var kokoroPlaybackVoiceID: String {
        if selectedVoiceModel == .kokoro {
            return selectedVoice
        }
        return Self.savedVoiceID(for: .kokoro)
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
        guard preset.modelFamily.supportsVoiceSamples else {
            log.warning("previewVoice() called for unavailable model \(preset.modelFamily.rawValue)")
            return
        }

        if previewingVoice == preset.id {
            stopVoicePreview()
            return
        }

        guard canPreview(preset) else {
            log.warning("previewVoice() called but sample is not ready")
            return
        }

        stopVoicePreview()
        previewingVoice = preset.id

        if let sampleURL = bundledSampleURL(for: preset) {
            playBundledVoicePreview(sampleURL, previewID: preset.id)
            return
        }

        previewTask = Task {
            do {
                let previewModel = try await self.sampleModel(for: preset.modelFamily)
                let params = previewModel.defaultGenerationParameters
                let sampleText = preset.sampleText
                let audio = try await previewModel.generate(
                    text: sampleText,
                    voice: preset.sampleVoicePrompt,
                    refAudio: nil,
                    refText: nil,
                    language: preset.sampleLanguage,
                    generationParameters: params
                )
                if Task.isCancelled { return }
                let samples = audio.asArray(Float.self)
                await MainActor.run {
                    guard self.previewingVoice == preset.id else { return }
                    self.playVoicePreview(
                        samples,
                        previewID: preset.id,
                        sampleRate: Double(previewModel.sampleRate)
                    )
                }
            } catch {
                log.error("Voice preview failed: \(error.localizedDescription)")
                await MainActor.run {
                    guard self.previewingVoice == preset.id else { return }
                    self.stopVoicePreview()
                }
            }
        }
    }

    private func sampleModel(for modelFamily: VoiceModelFamily) async throws -> any SpeechGenerationModel {
        switch modelFamily {
        case .kokoro:
            guard let model else {
                throw AudioGenerationError.modelNotInitialized("Kokoro model not loaded")
            }
            return model
        case .qwen:
            throw AudioGenerationError.invalidInput("Qwen samples are bundled audio files.")
        case .chatterbox:
            throw AudioGenerationError.invalidInput("Chatterbox samples need a Chatterbox runtime and reference audio.")
        }
    }

    private func bundledSampleURL(for preset: VoicePreset) -> URL? {
        guard let sampleName = preset.bundledSampleName else { return nil }
        return Bundle.main.url(
            forResource: sampleName,
            withExtension: "wav",
            subdirectory: "VoiceSamples"
        )
    }

    func stopVoicePreview() {
        previewTask?.cancel()
        previewTask = nil
        previewFileTask?.cancel()
        previewFileTask = nil
        previewFilePlayer?.stop()
        previewFilePlayer = nil
        previewPlayerNode?.stop()
        previewAudioEngine?.stop()
        previewPlayerNode = nil
        previewAudioEngine = nil
        previewingVoice = nil
    }

    private func playBundledVoicePreview(_ url: URL, previewID: String) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            previewFilePlayer = player
            player.prepareToPlay()
            player.play()

            let duration = max(player.duration, 0.1)
            previewFileTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                await MainActor.run {
                    guard let self, self.previewingVoice == previewID else { return }
                    self.stopVoicePreview()
                }
            }
            log.info("Bundled voice preview started for \(previewID)")
        } catch {
            log.error("Bundled voice preview failed: \(error.localizedDescription)")
            stopVoicePreview()
        }
    }

    private func playVoicePreview(_ samples: [Float], previewID: String, sampleRate: Double) {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

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
                    guard let self, self.previewingVoice == previewID else { return }
                    self.stopVoicePreview()
                }
            }
            player.play()
            log.info("Voice preview started for \(previewID)")
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
                        voice: self.kokoroPlaybackVoiceID,
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
                        self.scheduleStreamingAudio(samples, isFinalChunk: i == sentences.count - 1)
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

        accumulatedSamples.append(contentsOf: samples)
        totalSamplesScheduled += samples.count
        playbackChunksScheduled += 1
        let expectedGenID = self.generationID
        let expectedPlaybackID = self.playbackID

        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.generationID == expectedGenID else { return }
                guard self.playbackID == expectedPlaybackID else { return }
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
           (streamingGenerationComplete || bufferedAudioSeconds() >= resumeBufferTargetSeconds()) {
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
            self.accumulatedSamples = []
            self.seekSampleOffset = 0
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
                let playedSeconds = Double(seekSampleOffset) / Self.sampleRate + currentPlaybackSourceSeconds()
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
        let generatedSamples = accumulatedSamples.isEmpty ? totalSamplesScheduled : accumulatedSamples.count
        let remainingSamples = max(generatedSamples - seekSampleOffset, 0)
        return max(Double(remainingSamples) / Self.sampleRate - currentPlaybackSourceSeconds(), 0)
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
        accumulatedSamples = []
        seekSampleOffset = 0
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

    func skipBackward(_ seconds: Double = 15) {
        guard state == .playing || state == .paused, !accumulatedSamples.isEmpty else { return }
        let currentSample = seekSampleOffset + Int(currentPlaybackSourceSeconds() * Self.sampleRate)
        seekTo(sample: max(0, currentSample - Int(seconds * Self.sampleRate)))
    }

    func skipForward(_ seconds: Double = 15) {
        guard state == .playing || state == .paused, !accumulatedSamples.isEmpty else { return }
        let currentSample = seekSampleOffset + Int(currentPlaybackSourceSeconds() * Self.sampleRate)
        let target = min(currentSample + Int(seconds * Self.sampleRate), accumulatedSamples.count - 1)
        guard target > currentSample else { return }
        seekTo(sample: target)
    }

    private func seekTo(sample: Int) {
        guard let player = playerNode, let format = audioFormat else { return }
        let clamped = max(0, min(sample, accumulatedSamples.count - 1))
        let wasPlaying = state == .playing

        playbackID &+= 1
        player.stop()

        seekSampleOffset = clamped
        playbackChunksScheduled = 0
        playbackChunksCompleted = 0

        let remainingCount = accumulatedSamples.count - clamped
        guard remainingCount > 0 else { return }

        let frameCount = AVAudioFrameCount(remainingCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData?[0] else { return }
        accumulatedSamples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            memcpy(channelData, base.advanced(by: clamped), remainingCount * MemoryLayout<Float>.stride)
        }

        let expectedGenID = generationID
        let expectedPlaybackID = playbackID
        playbackChunksScheduled += 1
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard self.generationID == expectedGenID else { return }
                guard self.playbackID == expectedPlaybackID else { return }
                self.playbackChunksCompleted += 1
                if !self.streamingGenerationComplete,
                   self.streamingPlaybackStarted,
                   self.playbackChunksCompleted >= self.playbackChunksScheduled {
                    self.state = .generating
                    log.info("Seek buffer drained before generation finished; waiting for the next chunk")
                }
                self.finishPlaybackIfComplete()
            }
        }

        if wasPlaying { player.play() }
    }

    func updateSpeed(_ newSpeed: Double) {
        let clampedSpeed = min(max(newSpeed, 0.5), 2.0)
        speed = clampedSpeed
        timePitchNode?.rate = Float(clampedSpeed)
        log.info("Speed updated to \(clampedSpeed)x")
    }
}
