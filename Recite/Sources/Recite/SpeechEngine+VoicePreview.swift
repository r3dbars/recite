import AVFoundation
import Combine
import MLX
import MLXLMCommon
import MLXAudioTTS
import MLXAudioCore
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "SpeechEngine")

extension SpeechEngine {
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

        guard modelStatus == .ready, let model else {
            log.warning("previewVoice() called but model not ready")
            stopVoicePreview()
            return
        }

        previewTask = Task {
            do {
                let params = model.defaultGenerationParameters
                let audio = try await model.generate(
                    text: preset.sampleText,
                    voice: preset.generationVoicePrompt,
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
                        sampleRate: Double(model.sampleRate)
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

    func bundledSampleURL(for preset: VoicePreset) -> URL? {
        guard let sampleName = preset.bundledSampleName else { return nil }
        return Bundle.main.url(
            forResource: sampleName,
            withExtension: "wav",
            subdirectory: "VoiceSamples"
        )
    }

    func playBundledVoicePreview(_ url: URL, previewID: String) {
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

    func playVoicePreview(_ samples: [Float], previewID: String, sampleRate: Double) {
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
}
