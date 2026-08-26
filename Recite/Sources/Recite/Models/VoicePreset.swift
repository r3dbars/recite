struct VoicePreset: Identifiable, Hashable {
    let name: String
    let voiceID: String
    let modelFamily: VoiceModelFamily
    let detail: String

    var id: String { "\(modelFamily.rawValue):\(voiceID)" }

    var kokoroVoice: String { voiceID }

    var sampleText: String {
        switch modelFamily {
        case .kokoro:
            switch voiceID {
            case "af_heart": return "A calm voice for long articles and notes."
            case "af_bella": return "Soft and clear, with a little warmth."
            case "af_sky": return "Bright, steady, and easy to follow."
            case "af_nicole": return "A gentle voice for focused reading."
            case "af_sarah": return "Clean narration for emails and essays."
            case "af_nova": return "Modern and crisp, good for quick reads."
            case "af_river": return "Relaxed pacing for longer passages."
            case "am_adam": return "A grounded voice for plain spoken text."
            case "am_michael": return "Confident narration with a clear tone."
            case "am_eric": return "Direct and simple, good for short notes."
            case "am_liam": return "Light, natural, and conversational."
            case "bf_alice": return "A British voice for clear narration."
            case "bm_daniel": return "A steady British voice for longer reads."
            default: return "Recite can read selected text aloud on your Mac."
            }
        case .qwen:
            switch voiceID {
            case "Vivian": return "Hello, I am Vivian. This is a quick Recite voice sample."
            case "Serena": return "Hello, I am Serena. This is a quick Recite voice sample."
            case "Uncle_Fu": return "Hello, I am Uncle Fu. This is a quick Recite voice sample."
            case "Dylan": return "Hello, I am Dylan. This is a quick Recite voice sample."
            case "Eric": return "Hello, I am Eric. This is a quick Recite voice sample."
            case "Ryan": return "Hello, I am Ryan. This is a quick Recite voice sample."
            case "Aiden": return "Hello, I am Aiden. This is a quick Recite voice sample."
            case "Ono_Anna": return "Hello, I am Ono Anna. This is a quick Recite voice sample."
            case "Sohee": return "Hello, I am Sohee. This is a quick Recite voice sample."
            default: return "This Qwen voice can be used for local speech."
            }
        case .chatterbox:
            switch voiceID {
            case "default": return "A neutral Chatterbox sample voice."
            case "reference": return "This uses your saved reference voice."
            case "expressive": return "A more animated Chatterbox reading."
            default: return "This Chatterbox voice uses a reference sample."
            }
        }
    }

    var sampleLanguage: String {
        switch modelFamily {
        case .kokoro: return "en-us"
        case .qwen: return "English"
        case .chatterbox: return "en"
        }
    }

    var generationVoicePrompt: String? {
        switch modelFamily {
        case .kokoro:
            return voiceID
        case .qwen:
            switch voiceID {
            case "Vivian": return "Bright young female voice speaking English clearly and warmly."
            case "Serena": return "Warm gentle young female voice speaking English, soft and calm."
            case "Uncle_Fu": return "Seasoned older male voice speaking English with a mellow low tone."
            case "Dylan": return "Youthful male voice speaking English, crisp and clear."
            case "Eric": return "Lively male voice speaking English with upbeat energy."
            case "Ryan": return "Dynamic English male voice with rhythm and energy."
            case "Aiden": return "Sunny American male voice, friendly and easygoing."
            case "Ono_Anna": return "Playful Japanese female voice speaking English, bright and expressive."
            case "Sohee": return "Warm Korean female voice speaking English, gentle and clear."
            default: return nil
            }
        case .chatterbox:
            return nil
        }
    }

    var bundledSampleName: String? {
        switch modelFamily {
        case .kokoro:
            return nil
        case .qwen:
            return "qwen_\(voiceID)"
        case .chatterbox:
            return "chatterbox_\(voiceID)"
        }
    }

    static let defaultPreset = VoicePreset(
        name: "Heart",
        voiceID: "af_heart",
        modelFamily: .kokoro,
        detail: "American English · af_heart"
    )

    static let kokoroPresets: [VoicePreset] = [
        VoicePreset(name: "Heart", voiceID: "af_heart", modelFamily: .kokoro, detail: "American English · af_heart"),
        VoicePreset(name: "Bella", voiceID: "af_bella", modelFamily: .kokoro, detail: "American English · af_bella"),
        VoicePreset(name: "Sky", voiceID: "af_sky", modelFamily: .kokoro, detail: "American English · af_sky"),
        VoicePreset(name: "Nicole", voiceID: "af_nicole", modelFamily: .kokoro, detail: "American English · af_nicole"),
        VoicePreset(name: "Sarah", voiceID: "af_sarah", modelFamily: .kokoro, detail: "American English · af_sarah"),
        VoicePreset(name: "Nova", voiceID: "af_nova", modelFamily: .kokoro, detail: "American English · af_nova"),
        VoicePreset(name: "River", voiceID: "af_river", modelFamily: .kokoro, detail: "American English · af_river"),
        VoicePreset(name: "Adam", voiceID: "am_adam", modelFamily: .kokoro, detail: "American English · am_adam"),
        VoicePreset(name: "Michael", voiceID: "am_michael", modelFamily: .kokoro, detail: "American English · am_michael"),
        VoicePreset(name: "Eric", voiceID: "am_eric", modelFamily: .kokoro, detail: "American English · am_eric"),
        VoicePreset(name: "Liam", voiceID: "am_liam", modelFamily: .kokoro, detail: "American English · am_liam"),
        VoicePreset(name: "Alice (British)", voiceID: "bf_alice", modelFamily: .kokoro, detail: "British English · bf_alice"),
        VoicePreset(name: "Daniel (British)", voiceID: "bm_daniel", modelFamily: .kokoro, detail: "British English · bm_daniel"),
    ]

    static let qwenPresets: [VoicePreset] = [
        VoicePreset(name: "Vivian", voiceID: "Vivian", modelFamily: .qwen, detail: "Bright young voice"),
        VoicePreset(name: "Serena", voiceID: "Serena", modelFamily: .qwen, detail: "Warm young voice"),
        VoicePreset(name: "Uncle Fu", voiceID: "Uncle_Fu", modelFamily: .qwen, detail: "Low seasoned voice"),
        VoicePreset(name: "Dylan", voiceID: "Dylan", modelFamily: .qwen, detail: "Clear Beijing voice"),
        VoicePreset(name: "Eric", voiceID: "Eric", modelFamily: .qwen, detail: "Lively Chengdu voice"),
        VoicePreset(name: "Ryan", voiceID: "Ryan", modelFamily: .qwen, detail: "Dynamic English voice"),
        VoicePreset(name: "Aiden", voiceID: "Aiden", modelFamily: .qwen, detail: "Sunny American voice"),
        VoicePreset(name: "Ono Anna", voiceID: "Ono_Anna", modelFamily: .qwen, detail: "Playful Japanese voice"),
        VoicePreset(name: "Sohee", voiceID: "Sohee", modelFamily: .qwen, detail: "Warm Korean voice"),
    ]

    static let chatterboxPresets: [VoicePreset] = [
        VoicePreset(name: "Default", voiceID: "default", modelFamily: .chatterbox, detail: "Built-in fallback voice"),
        VoicePreset(name: "Reference Voice", voiceID: "reference", modelFamily: .chatterbox, detail: "Use a saved reference clip"),
        VoicePreset(name: "Expressive", voiceID: "expressive", modelFamily: .chatterbox, detail: "Higher emotion setting"),
    ]

    static func catalog(for modelFamily: VoiceModelFamily) -> [VoicePreset] {
        switch modelFamily {
        case .kokoro: return kokoroPresets
        case .qwen: return qwenPresets
        case .chatterbox: return chatterboxPresets
        }
    }

    static func resolvedVoiceID(_ candidate: String?, family: VoiceModelFamily) -> String {
        let presets = catalog(for: family)
        let fallback = presets.first?.voiceID ?? defaultPreset.voiceID
        guard let candidate, presets.contains(where: { $0.voiceID == candidate }) else {
            return fallback
        }
        return candidate
    }
}
