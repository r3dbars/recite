import AVFoundation
import Combine

/// Text-to-speech engine wrapping AVSpeechSynthesizer.
/// v1: Uses Apple Neural Voice (on-device, zero setup, surprisingly good).
/// v2 path: swap synthesiser for Kokoro once CoreML model is ready.
class SpeechEngine: NSObject, ObservableObject {
    static let shared = SpeechEngine()

    enum State { case idle, playing, paused }

    @Published var state: State = .idle
    @Published var currentText: String = ""
    @Published var progress: Double = 0
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate  // 0.0 – 1.0
    @Published var selectedVoiceIdentifier: String = ""

    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var fullTextLength: Int = 0

    override init() {
        super.init()
        synthesizer.delegate = self
        // Default to best available English Neural voice
        selectedVoiceIdentifier = bestEnglishVoice()?.identifier ?? ""
    }

    // MARK: - Playback

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.voice = voice(for: selectedVoiceIdentifier)
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        currentText = text
        fullTextLength = text.count
        progress = 0
        currentUtterance = utterance

        synthesizer.speak(utterance)
        state = .playing
    }

    func pause() {
        guard state == .playing else { return }
        synthesizer.pauseSpeaking(at: .word)
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        synthesizer.continueSpeaking()
        state = .playing
    }

    func stop() {
        synthesizer.stopSpeaking(at: .word)
        state = .idle
        currentText = ""
        progress = 0
    }

    func togglePlayPause() {
        switch state {
        case .playing: pause()
        case .paused:  resume()
        case .idle:    ReadingQueue.shared.playNext()
        }
    }

    func playNext() {
        stop()
        ReadingQueue.shared.playNext()
    }

    func updateRate(_ newRate: Float) {
        rate = newRate
        // If currently playing, restart current item at new rate
        if state == .playing, let text = currentUtterance?.speechString {
            stop()
            speak(text)
        }
    }

    // MARK: - Voices

    var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    private func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        // Prefer "Enhanced" or "Premium" Neural voices (on-device, higher quality)
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-US") }

        // macOS 14+: quality enum
        if #available(macOS 14.0, *) {
            if let premium = voices.first(where: { $0.quality == .premium }) { return premium }
            if let enhanced = voices.first(where: { $0.quality == .enhanced }) { return enhanced }
        }
        return voices.first { $0.name.contains("Samantha") } ?? voices.first
    }

    private func voice(for identifier: String) -> AVSpeechSynthesisVoice? {
        guard !identifier.isEmpty else { return bestEnglishVoice() }
        return AVSpeechSynthesisVoice(identifier: identifier) ?? bestEnglishVoice()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechEngine: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didStart utterance: AVSpeechUtterance) {
        state = .playing
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        guard fullTextLength > 0 else { return }
        let end = characterRange.location + characterRange.length
        progress = Double(end) / Double(fullTextLength)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        progress = 1.0
        state = .idle
        currentText = ""
        // Auto-advance queue
        ReadingQueue.shared.didFinishCurrent()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didPause utterance: AVSpeechUtterance) {
        state = .paused
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didContinue utterance: AVSpeechUtterance) {
        state = .playing
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        state = .idle
    }
}
