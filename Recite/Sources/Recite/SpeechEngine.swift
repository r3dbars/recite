import AVFoundation
import Combine
import MLX
import MLXLMCommon
import MLXAudioTTS
import MLXAudioCore
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "SpeechEngine")

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
    static let executablePaths = [
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

    static var bundledExecutableURL: URL? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("espeak-ng")
    }

    static var bundledDataParentURL: URL? {
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

/// Text-to-speech engine powered by local MLX text-to-speech models.
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
    @Published var selectedSpeechModelID: String = SpeechEngine.savedSpeechModelID() {
        didSet {
            guard selectedSpeechModelID != oldValue else { return }
            guard Self.speechModels.contains(where: { $0.id == selectedSpeechModelID }) else {
                selectedSpeechModelID = Self.defaultSpeechModel.id
                return
            }

            log.info("Speech model changed to: \(self.selectedSpeechModelID)")
            UserDefaults.standard.set(selectedSpeechModelID, forKey: Self.selectedSpeechModelKey)
            stopVoicePreview()
            selectedVoice = Self.savedVoiceID(for: selectedSpeechModel.voiceFamily)
            stop()
            model = nil
            loadedSpeechModelID = nil
            modelStatus = .notLoaded
            Task { await self.loadModel() }
        }
    }
    @Published private(set) var selectedVoice: String = SpeechEngine.savedVoiceID(
        for: SpeechEngine.savedSpeechModel().voiceFamily
    )

    static let voicePresets = VoicePreset.kokoroPresets
    static let qwenVoicePresets = VoicePreset.qwenPresets
    static let chatterboxVoicePresets = VoicePreset.chatterboxPresets
    static let defaultSpeechModel = SpeechModelPreset.kokoro
    static let speechModels = SpeechModelPreset.all

    var selectedSpeechModel: SpeechModelPreset {
        Self.speechModels.first { $0.id == selectedSpeechModelID } ?? Self.defaultSpeechModel
    }

    var model: (any SpeechGenerationModel)?
    var loadedSpeechModelID: String?
    var generationTask: Task<Void, Never>?

    // Generation ID: incremented on each speak() call so stale callbacks are ignored
    var generationID: UInt64 = 0

    // Audio playback via AVAudioEngine
    var audioEngine: AVAudioEngine?
    var playerNode: AVAudioPlayerNode?
    var timePitchNode: AVAudioUnitTimePitch?
    var audioFormat: AVAudioFormat?
    var totalSamplesScheduled = 0
    var playbackChunksScheduled = 0
    var playbackChunksCompleted = 0
    var streamingGenerationComplete = false
    var streamingPlaybackStarted = false
    var accumulatedSamples: [Float] = []
    var seekSampleOffset: Int = 0
    var playbackID: UInt64 = 0
    var progressTask: Task<Void, Never>?
    var previewTask: Task<Void, Never>?
    var previewAudioEngine: AVAudioEngine?
    var previewPlayerNode: AVAudioPlayerNode?
    var previewFilePlayer: AVAudioPlayer?
    var previewFileTask: Task<Void, Never>?

    var playbackSampleRate: Double = 24000
    static let fastEnoughMargin = 1.15
    static let minimumStartupBufferSeconds = 1.25
    static let comfortableStartupBufferSeconds = 3.0
    static let lowWaterWallSeconds = 2.5
    static let selectedSpeechModelKey = "selectedSpeechModelID"
    static let legacySelectedVoiceKey = "selectedVoice"

    override init() {
        super.init()
    }

    static func voicePresets(for modelFamily: VoiceModelFamily) -> [VoicePreset] {
        VoicePreset.catalog(for: modelFamily)
    }

    func selectVoice(_ preset: VoicePreset) {
        guard preset.modelFamily == selectedSpeechModel.voiceFamily else { return }
        guard selectedVoice != preset.voiceID else { return }
        stopVoicePreview()
        selectedVoice = preset.voiceID
        persistSelectedVoice(for: preset.modelFamily)
        log.info("Voice changed to: \(self.selectedVoice)")
        restartPlaybackIfNeeded(for: preset.modelFamily)
    }

    func canPreview(_ preset: VoicePreset) -> Bool {
        guard preset.modelFamily.supportsVoiceSamples else { return false }
        guard state == .idle else { return false }
        if bundledSampleURL(for: preset) != nil {
            return true
        }
        guard preset.modelFamily == .kokoro else { return false }
        return selectedSpeechModel.voiceFamily == .kokoro && modelStatus == .ready
    }

    static func savedSpeechModelID() -> String {
        let saved = UserDefaults.standard.string(forKey: selectedSpeechModelKey)
        guard let saved, speechModels.contains(where: { $0.id == saved }) else {
            return defaultSpeechModel.id
        }
        return saved
    }

    static func savedSpeechModel() -> SpeechModelPreset {
        let savedID = savedSpeechModelID()
        return speechModels.first { $0.id == savedID } ?? defaultSpeechModel
    }

    static func voiceDefaultsKey(for modelFamily: VoiceModelFamily) -> String {
        "selectedVoice.\(modelFamily.rawValue)"
    }

    static func savedVoiceID(for modelFamily: VoiceModelFamily) -> String {
        let saved = UserDefaults.standard.string(forKey: voiceDefaultsKey(for: modelFamily))
        let legacySaved = modelFamily == .kokoro
            ? UserDefaults.standard.string(forKey: legacySelectedVoiceKey)
            : nil
        return VoicePreset.resolvedVoiceID(saved ?? legacySaved, family: modelFamily)
    }

    func persistSelectedVoice(for modelFamily: VoiceModelFamily) {
        UserDefaults.standard.set(selectedVoice, forKey: Self.voiceDefaultsKey(for: modelFamily))
        if modelFamily == .kokoro {
            UserDefaults.standard.set(selectedVoice, forKey: Self.legacySelectedVoiceKey)
        }
    }

    func restartPlaybackIfNeeded(for modelFamily: VoiceModelFamily) {
        guard state == .playing || state == .paused || state == .generating else { return }
        guard modelFamily == selectedSpeechModel.voiceFamily else { return }
        let textToRepeat = currentText.isEmpty ? ReadingQueue.shared.currentItem?.text : currentText
        if let text = textToRepeat {
            speak(text)
        }
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
