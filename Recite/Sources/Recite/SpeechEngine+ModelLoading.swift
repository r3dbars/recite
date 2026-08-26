import AVFoundation
import Combine
import MLX
import MLXLMCommon
import MLXAudioTTS
import MLXAudioCore
import os.log

private let log = Logger(subsystem: "com.r3dbars.recite", category: "SpeechEngine")

extension SpeechEngine {
    func isModelCached(_ preset: SpeechModelPreset) -> Bool {
        // Mirrors ModelUtils.resolveOrDownloadModel path logic:
        // <HubCache.default.cacheDirectory>/mlx-audio/<repo-with-slashes-replaced>/
        let cacheDir = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".cache/huggingface/hub")
        let modelDir = cacheDir
            .appendingPathComponent("mlx-audio")
            .appendingPathComponent(preset.modelID.replacingOccurrences(of: "/", with: "_"))
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
        let preset = selectedSpeechModel
        guard loadedSpeechModelID != preset.id || modelStatus == .notLoaded || isErrorStatus else {
            log.info("loadModel() skipped — modelStatus=\(String(describing: self.modelStatus))")
            return
        }
        log.info("loadModel() starting for \(preset.modelID)")
        if isModelCached(preset) {
            modelStatus = .loading
            log.info("Model found in cache — loading weights")
        } else {
            modelStatus = .downloading(progress: 0.0)
            log.info("Model not in cache — downloading from HuggingFace")
        }

        do {
            let textProcessor: TextProcessor? = preset.requiresEspeakTextProcessor
                ? EspeakTextProcessor()
                : nil
            let loaded = try await TTS.loadModel(
                modelRepo: preset.modelID,
                textProcessor: textProcessor
            )
            guard self.selectedSpeechModel.id == preset.id else { return }
            self.model = loaded
            self.loadedSpeechModelID = preset.id
            self.playbackSampleRate = Double(loaded.sampleRate)
            modelStatus = .ready
            log.info("\(preset.name) model loaded successfully")
            if state == .idle, let item = ReadingQueue.shared.currentItem {
                speak(item.text)
            }
        } catch {
            log.error("Model load failed: \(error.localizedDescription)")
            modelStatus = .error(error.localizedDescription)
        }
    }

    var isErrorStatus: Bool {
        if case .error = modelStatus { return true }
        return false
    }
}
