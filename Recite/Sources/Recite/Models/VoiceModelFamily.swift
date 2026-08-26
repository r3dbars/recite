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

    var supportsVoiceSamples: Bool {
        true
    }

    var sampleUnavailableReason: String? {
        nil
    }
}
