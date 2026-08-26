import AVFoundation
import Combine
import MLX
import MLXLMCommon
import MLXAudioTTS
import MLXAudioCore
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "SpeechEngine")

extension SpeechEngine {
    func scheduleStreamingAudio(_ samples: [Float], isFinalChunk: Bool) {
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
        log.info("Scheduled streaming chunk \(self.playbackChunksScheduled, privacy: .public): \(String(format: "%.2f", Double(samples.count) / self.playbackSampleRate), privacy: .public)s audio")
    }

    func setupAudioEngine() -> Bool {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.rate = Float(speed)
        let format = AVAudioFormat(standardFormatWithSampleRate: playbackSampleRate, channels: 1)!

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

    func startProgressTracker(totalEstimatedAudioSeconds: @escaping @MainActor () -> Double) {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled && (state == .generating || state == .playing || state == .paused) {
                let playedSeconds = Double(seekSampleOffset) / playbackSampleRate + currentPlaybackSourceSeconds()
                let totalSeconds = max(totalEstimatedAudioSeconds(), Double(totalSamplesScheduled) / playbackSampleRate)
                if totalSeconds > 0 {
                    progress = min(playedSeconds / totalSeconds, 0.99)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func currentPlaybackSourceSeconds() -> Double {
        guard let player = playerNode,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return max(Double(playerTime.sampleTime) / playbackSampleRate, 0)
    }

    func bufferedAudioSeconds() -> Double {
        let generatedSamples = accumulatedSamples.isEmpty ? totalSamplesScheduled : accumulatedSamples.count
        let remainingSamples = max(generatedSamples - seekSampleOffset, 0)
        return max(Double(remainingSamples) / playbackSampleRate - currentPlaybackSourceSeconds(), 0)
    }

    func resumeBufferTargetSeconds() -> Double {
        max(Self.minimumStartupBufferSeconds * speed, 0.5)
    }

    func finishPlaybackIfComplete() {
        guard streamingGenerationComplete,
              playbackChunksScheduled > 0,
              playbackChunksCompleted >= playbackChunksScheduled else {
            return
        }
        finishPlayback()
    }

    func finishPlayback() {
        progressTask?.cancel()
        progressTask = nil
        progress = 1.0
        state = .idle
        currentText = ""
        stopAudioEngine()
        ReadingQueue.shared.didFinishCurrent()
    }

    func stopAudioEngine() {
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

    func skipBackward(_ seconds: Double = 15) {
        guard state == .playing || state == .paused, !accumulatedSamples.isEmpty else { return }
        let currentSample = seekSampleOffset + Int(currentPlaybackSourceSeconds() * playbackSampleRate)
        seekTo(sample: max(0, currentSample - Int(seconds * playbackSampleRate)))
    }

    func skipForward(_ seconds: Double = 15) {
        guard state == .playing || state == .paused, !accumulatedSamples.isEmpty else { return }
        let currentSample = seekSampleOffset + Int(currentPlaybackSourceSeconds() * playbackSampleRate)
        let target = min(currentSample + Int(seconds * playbackSampleRate), accumulatedSamples.count - 1)
        guard target > currentSample else { return }
        seekTo(sample: target)
    }

    func seekTo(sample: Int) {
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
}
