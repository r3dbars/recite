import XCTest
@testable import Recite

@MainActor
final class VoicePresetTests: XCTestCase {
    func testCatalogCounts() {
        XCTAssertEqual(VoicePreset.kokoroPresets.count, 13)
        XCTAssertEqual(VoicePreset.qwenPresets.count, 9)
        XCTAssertEqual(VoicePreset.chatterboxPresets.count, 3)
        XCTAssertEqual(SpeechModelPreset.all.count, 3)
        XCTAssertEqual(SpeechEngine.voicePresets.count, 13)
        XCTAssertEqual(SpeechEngine.qwenVoicePresets.count, 9)
        XCTAssertEqual(SpeechEngine.chatterboxVoicePresets.count, 3)
        XCTAssertEqual(SpeechEngine.speechModels.count, 3)
    }

    func testCatalogLookupMatchesFamily() {
        XCTAssertEqual(VoicePreset.catalog(for: .kokoro).count, 13)
        XCTAssertEqual(VoicePreset.catalog(for: .qwen).count, 9)
        XCTAssertEqual(VoicePreset.catalog(for: .chatterbox).count, 3)
        XCTAssertTrue(VoicePreset.catalog(for: .kokoro).allSatisfy { $0.modelFamily == .kokoro })
        XCTAssertTrue(VoicePreset.catalog(for: .qwen).allSatisfy { $0.modelFamily == .qwen })
        XCTAssertTrue(VoicePreset.catalog(for: .chatterbox).allSatisfy { $0.modelFamily == .chatterbox })
    }

    func testVoiceIDFallback() {
        XCTAssertEqual(VoicePreset.defaultPreset.voiceID, "af_heart")
        XCTAssertEqual(VoicePreset.resolvedVoiceID(nil, family: .kokoro), "af_heart")
        XCTAssertEqual(VoicePreset.resolvedVoiceID("not-a-voice", family: .kokoro), "af_heart")
        XCTAssertEqual(VoicePreset.resolvedVoiceID("af_bella", family: .kokoro), "af_bella")
        XCTAssertEqual(VoicePreset.resolvedVoiceID("missing", family: .qwen), "Vivian")
        XCTAssertEqual(VoicePreset.resolvedVoiceID("Serena", family: .qwen), "Serena")
        XCTAssertEqual(VoicePreset.resolvedVoiceID("nope", family: .chatterbox), "default")
        XCTAssertEqual(VoicePreset.resolvedVoiceID("reference", family: .chatterbox), "reference")
    }
}
