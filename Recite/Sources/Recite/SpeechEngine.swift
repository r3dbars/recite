import AVFoundation
import Combine
import MLX
import MLXLMCommon
import MLXAudioTTS
import MLXAudioCore

/// Text-to-speech engine powered by Qwen3-TTS via mlx-audio-swift.
/// Runs entirely on-device using MLX on Apple Silicon.
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

    private var model: Qwen3TTSModel?
    private var audioPlayer: AVAudioPlayer?
    private var generationTask: Task<Void, Never>?

    private static let modelID = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    private static let sampleRate: Double = 24000

    override init() {
        super.init()
    }

    // MARK: - Model Loading

    /// Load the Qwen3-TTS model. Call once at app launch.
    func loadModel() async {
        guard modelStatus == .notLoaded || isErrorStatus else { return }
        modelStatus = .loading

        do {
            let loaded = try await Qwen3TTSModel.fromPretrained(Self.modelID)
            self.model = loaded
            modelStatus = .ready
        } catch {
            modelStatus = .error(error.localizedDescription)
        }
    }

    private var isErrorStatus: Bool {
        if case .error = modelStatus { return true }
        return false
    }

    // MARK: - Playback

    func speak(_ text: String) {
        guard modelStatus == .ready, let model = model else { return }

        // Cancel any in-progress generation
        generationTask?.cancel()
        audioPlayer?.stop()

        currentText = text
        progress = 0
        state = .generating

        generationTask = Task {
            do {
                let params = GenerateParameters(
                    maxTokens: 4096,
                    temperature: 0.7,
                    topP: 0.95,
                    repetitionPenalty: 1.5,
                    repetitionContextSize: 30
                )

                let audioArray = try await model.generate(
                    text: text,
                    voice: nil,
                    refAudio: nil,
                    refText: nil,
                    language: nil,
                    generationParameters: params
                )

                if Task.isCancelled { return }

                // Convert MLXArray audio to WAV data and play
                let audioData = try audioToWAV(audioArray, sampleRate: Self.sampleRate)
                try playAudio(audioData)

            } catch {
                if !Task.isCancelled {
                    state = .idle
                    currentText = ""
                }
            }
        }
    }

    func pause() {
        guard state == .playing, let player = audioPlayer else { return }
        player.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused, let player = audioPlayer else { return }
        player.play()
        state = .playing
    }

    func stop() {
        generationTask?.cancel()
        audioPlayer?.stop()
        audioPlayer = nil
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
        audioPlayer?.rate = Float(newSpeed)
    }

    // MARK: - Audio Playback

    private func playAudio(_ data: Data) throws {
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.enableRate = true
        player.rate = Float(speed)
        player.play()
        self.audioPlayer = player
        state = .playing

        // Start progress tracking
        trackProgress(player: player)
    }

    private func trackProgress(player: AVAudioPlayer) {
        Task {
            while player.isPlaying || state == .paused {
                if state == .playing, player.duration > 0 {
                    progress = player.currentTime / player.duration
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }

    // MARK: - WAV Encoding

    private func audioToWAV(_ audioArray: MLXArray, sampleRate: Double) throws -> Data {
        // Convert MLXArray to Float32 samples
        let samples = audioArray.asArray(Float.self)
        let numSamples = samples.count
        let bytesPerSample = 2 // 16-bit PCM
        let dataSize = numSamples * bytesPerSample

        var data = Data()

        // WAV header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * Double(bytesPerSample)).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(bytesPerSample).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) }) // bits per sample

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Convert float samples to 16-bit PCM
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        return data
    }
}

// MARK: - AVAudioPlayerDelegate

extension SpeechEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            progress = 1.0
            state = .idle
            currentText = ""
            ReadingQueue.shared.didFinishCurrent()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            state = .idle
            currentText = ""
        }
    }
}
