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
    let instruct: String

    static let defaultPreset = VoicePreset(
        name: "Calm Female",
        instruct: "A calm, clear female voice with a neutral American accent, speaking at a moderate pace."
    )
}

/// Text-to-speech engine powered by Qwen3-TTS via mlx-audio-swift.
/// Uses streaming generation so audio starts playing within seconds.
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
    @Published var voiceInstruct: String = VoicePreset.defaultPreset.instruct {
        didSet { log.info("Voice changed to: \(self.voiceInstruct)") }
    }

    static let voicePresets: [VoicePreset] = [
        VoicePreset(name: "Calm Female", instruct: "A calm, clear female voice with a neutral American accent, speaking at a moderate pace."),
        VoicePreset(name: "Warm Male", instruct: "A warm, deep male voice with a friendly tone, speaking at a relaxed pace."),
        VoicePreset(name: "Energetic Female", instruct: "An energetic young female voice with an upbeat and lively tone."),
        VoicePreset(name: "Professional Male", instruct: "A professional male voice with a clear, authoritative tone suitable for narration."),
        VoicePreset(name: "Gentle Female", instruct: "A gentle, soft-spoken female voice with a soothing and reassuring tone."),
        VoicePreset(name: "British Male", instruct: "A refined British male voice with clear enunciation and a composed delivery."),
    ]

    private var model: Qwen3TTSModel?
    private var generationTask: Task<Void, Never>?

    // Generation ID: incremented on each speak() call so stale callbacks are ignored
    private var generationID: UInt64 = 0

    // Streaming audio playback via AVAudioEngine
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var scheduledBufferCount = 0
    private var completedBufferCount = 0
    private var totalSamplesScheduled = 0
    private var isStreamComplete = false

    private static let modelID = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit"
    private static let sampleRate: Double = 24000

    override init() {
        super.init()
    }

    // MARK: - Model Loading

    func loadModel() async {
        guard modelStatus == .notLoaded || isErrorStatus else {
            log.info("loadModel() skipped — modelStatus=\(String(describing: self.modelStatus))")
            return
        }
        log.info("loadModel() starting...")
        modelStatus = .loading

        do {
            let loaded = try await Qwen3TTSModel.fromPretrained(Self.modelID)
            self.model = loaded
            modelStatus = .ready
            log.info("Model loaded successfully")
        } catch {
            log.error("Model load failed: \(error.localizedDescription)")
            modelStatus = .error(error.localizedDescription)
        }
    }

    private var isErrorStatus: Bool {
        if case .error = modelStatus { return true }
        return false
    }

    // MARK: - Streaming Playback

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
        isStreamComplete = false
        scheduledBufferCount = 0
        completedBufferCount = 0
        totalSamplesScheduled = 0

        // Increment generation ID so stale callbacks from previous speak() are ignored
        generationID &+= 1
        let myGenID = generationID
        log.info("Starting generation #\(myGenID)")

        // Set up audio engine for streaming playback
        setupAudioEngine()

        generationTask = Task {
            do {
                let params = GenerateParameters(
                    maxTokens: 4096,
                    temperature: 0.7,
                    topP: 0.95,
                    repetitionPenalty: 1.5,
                    repetitionContextSize: 30
                )

                let voice = self.voiceInstruct.isEmpty ? nil : self.voiceInstruct
                log.info("Starting streaming generation with voice=\(voice ?? "nil", privacy: .public)")

                let stream = model.generateStream(
                    text: text,
                    voice: voice,
                    refAudio: nil,
                    refText: nil,
                    language: nil,
                    generationParameters: params,
                    streamingInterval: 1.0
                )

                let chunksBeforePlay = 5 // Buffer 5 chunks (~4.8s) before starting playback
                var chunkIndex = 0
                for try await event in stream {
                    if Task.isCancelled {
                        log.info("Stream cancelled")
                        return
                    }

                    switch event {
                    case .audio(let audioChunk):
                        chunkIndex += 1
                        let samples = audioChunk.asArray(Float.self)
                        log.info("Audio chunk #\(chunkIndex): \(samples.count) samples (gen #\(myGenID))")

                        await MainActor.run {
                            guard self.generationID == myGenID else { return }
                            scheduleAudioChunk(samples)

                            // Start playing after buffering enough chunks for smooth playback
                            if chunkIndex == chunksBeforePlay {
                                startPlayback()
                            }
                        }

                    case .info(let info):
                        log.info("Generation info: tokensPerSecond=\(info.tokensPerSecond ?? 0)")

                    case .token:
                        break
                    }
                }

                await MainActor.run {
                    // Only mark complete if this is still the active generation
                    guard self.generationID == myGenID else {
                        log.info("Stream complete for stale generation #\(myGenID), ignoring")
                        return
                    }
                    isStreamComplete = true
                    log.info("Stream complete, \(chunkIndex) chunks total (gen #\(myGenID))")
                    // If we never hit the buffer threshold, start playback now
                    if chunkIndex > 0 && chunkIndex < chunksBeforePlay {
                        startPlayback()
                    }
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

    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Apply speed via rate adjustment
        // AVAudioPlayerNode doesn't have a rate property, so we use AVAudioUnitTimePitch
        // For now, keep at 1x during streaming — speed is applied at engine level

        do {
            try engine.start()
            self.audioEngine = engine
            self.playerNode = player
            self.audioFormat = format
            log.info("Audio engine started")
        } catch {
            log.error("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    private func scheduleAudioChunk(_ samples: [Float]) {
        guard let player = playerNode, let format = audioFormat else { return }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        // Copy samples into the buffer
        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = max(-1.0, min(1.0, samples[i]))
        }

        scheduledBufferCount += 1
        totalSamplesScheduled += samples.count
        let bufferIndex = scheduledBufferCount

        let expectedGenID = self.generationID
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Ignore callbacks from a previous generation
                guard self.generationID == expectedGenID else { return }
                self.completedBufferCount += 1
                if self.isStreamComplete && self.completedBufferCount >= self.scheduledBufferCount {
                    log.info("All buffers played, finishing (gen #\(expectedGenID))")
                    self.finishPlayback()
                }
            }
        }

        let total = self.totalSamplesScheduled
        log.info("Scheduled buffer #\(bufferIndex) (\(samples.count) samples, total=\(total))")
    }

    private func startPlayback() {
        guard let player = playerNode else { return }
        player.play()
        state = .playing
        log.info("Playback started (streaming)")

        // Track progress
        Task {
            while state == .playing || state == .generating || state == .paused {
                if let player = playerNode, let nodeTime = player.lastRenderTime,
                   let playerTime = player.playerTime(forNodeTime: nodeTime),
                   totalSamplesScheduled > 0 {
                    let currentSample = Double(playerTime.sampleTime)
                    let total = Double(totalSamplesScheduled)
                    progress = min(currentSample / total, 1.0)
                }
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            }
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
    }
}
