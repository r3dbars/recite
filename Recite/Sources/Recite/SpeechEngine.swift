import AVFoundation
import Combine
import TTSKit
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "SpeechEngine")

/// Text-to-speech engine powered by Qwen3-TTS via TTSKit (CoreML/Neural Engine).
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
    @Published var selectedSpeaker: Qwen3Speaker = .serena {
        didSet { log.info("Speaker changed to: \(self.selectedSpeaker.displayName)") }
    }

    static let availableSpeakers: [Qwen3Speaker] = [
        .serena, .vivian, .ryan, .aiden,
        .sohee, .onoAnna, .eric, .dylan, .uncleFu
    ]

    private var tts: TTSKit?
    private var producerTask: Task<Void, Never>?
    private var consumerTask: Task<Void, Never>?

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
            let config = TTSKitConfig(model: .qwen3TTS_0_6b)
            let loaded = try await TTSKit(config)
            self.tts = loaded
            modelStatus = .ready
            log.info("TTSKit model loaded successfully")
        } catch {
            log.error("TTSKit load failed: \(error.localizedDescription)")
            modelStatus = .error(error.localizedDescription)
        }
    }

    private var isErrorStatus: Bool {
        if case .error = modelStatus { return true }
        return false
    }

    // MARK: - Streaming Playback

    func speak(_ text: String) {
        guard modelStatus == .ready, let tts = tts else {
            log.warning("speak() called but model not ready (modelStatus=\(String(describing: self.modelStatus)))")
            return
        }

        log.info("speak() called with \(text.count) chars")

        // Cancel any in-progress generation
        producerTask?.cancel()
        consumerTask?.cancel()
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

        // Capture MainActor-isolated values for use in producer task
        let speaker = self.selectedSpeaker

        // AsyncStream bridges TTSKit's @Sendable callback to MainActor consumption
        let (stream, continuation) = AsyncStream<[Float]>.makeStream()

        // Producer: TTSKit generates audio via CoreML/ANE, yields chunks to stream
        producerTask = Task {
            defer { continuation.finish() }
            do {
                let _ = try await tts.generate(
                    text: text,
                    speaker: speaker,
                    language: .english
                ) { progress in
                    if Task.isCancelled { return false }
                    if !progress.audio.isEmpty {
                        continuation.yield(progress.audio)
                    }
                    return true
                }
                log.info("Generation complete (gen #\(myGenID))")
            } catch {
                if !Task.isCancelled {
                    log.error("Generation error: \(error.localizedDescription)")
                }
            }
        }

        // Consumer: reads chunks from stream, schedules on AVAudioEngine
        // TTSKit delivers ~80ms chunks (1920 samples at 24kHz)
        // Start playback after 5 chunks (~400ms buffer)
        let chunksBeforePlay = 5
        log.info("Buffer: start after \(chunksBeforePlay) chunks (~\(chunksBeforePlay * 80)ms)")

        consumerTask = Task {
            var chunkIndex = 0

            for await samples in stream {
                guard self.generationID == myGenID else { break }
                if Task.isCancelled { break }

                chunkIndex += 1
                log.info("Audio chunk #\(chunkIndex): \(samples.count) samples (gen #\(myGenID))")
                self.scheduleAudioChunk(samples)

                // Start playing after buffering enough chunks for smooth playback
                if chunkIndex == chunksBeforePlay {
                    self.startPlayback()
                }
            }

            guard self.generationID == myGenID else {
                log.info("Stream complete for stale generation #\(myGenID), ignoring")
                return
            }
            self.isStreamComplete = true
            log.info("Stream complete, \(chunkIndex) chunks total (gen #\(myGenID))")
            // If we never hit the buffer threshold, start playback now
            if chunkIndex > 0 && chunkIndex < chunksBeforePlay {
                self.startPlayback()
            }
        }
    }

    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

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
                guard self.generationID == expectedGenID else { return }
                self.completedBufferCount += 1
                if self.completedBufferCount >= self.scheduledBufferCount {
                    if self.isStreamComplete {
                        log.info("All buffers played, finishing (gen #\(expectedGenID))")
                        self.finishPlayback()
                    } else {
                        // Buffer underrun — generation can't keep up. Pause until more audio arrives.
                        log.info("Buffer underrun at chunk \(self.completedBufferCount), pausing (gen #\(expectedGenID))")
                        self.playerNode?.pause()
                        self.state = .generating
                    }
                }
            }
        }

        // If we were paused due to buffer underrun, resume now that we have a new chunk
        if state == .generating, let player = playerNode, completedBufferCount > 0 {
            let bufferedAhead = scheduledBufferCount - completedBufferCount
            if bufferedAhead >= 2 { // Resume after 2 chunks of headroom
                player.play()
                state = .playing
                log.info("Resumed after buffer underrun (gen #\(expectedGenID))")
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
        producerTask?.cancel()
        consumerTask?.cancel()
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
