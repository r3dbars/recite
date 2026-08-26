import AVFoundation
import Combine
import MLX
import MLXLMCommon
import MLXAudioTTS
import MLXAudioCore
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "SpeechEngine")

extension SpeechEngine {
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
                let sentences = TextPreprocessor.splitIntoSentences(text)
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

                    let params = model.defaultGenerationParameters
                    let audio = try await model.generate(
                        text: trimmed,
                        voice: self.voiceParameter(for: self.selectedSpeechModel),
                        refAudio: nil,
                        refText: nil,
                        language: self.selectedSpeechModel.language,
                        generationParameters: params
                    )

                    let samples = audio.asArray(Float.self)
                    let chunkAudioSeconds = Double(samples.count) / self.playbackSampleRate
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

    func estimateTotalAudioSeconds(
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
    func startupBufferTargetSeconds(
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

    func voiceParameter(for preset: SpeechModelPreset) -> String? {
        if preset.supportsKokoroVoices {
            return selectedVoice
        }
        return Self.voicePresets(for: preset.voiceFamily)
            .first { $0.voiceID == selectedVoice }?
            .generationVoicePrompt ?? preset.voicePrompt
    }
}
