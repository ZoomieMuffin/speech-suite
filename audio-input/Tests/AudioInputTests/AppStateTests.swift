import Foundation
import Testing
@testable import AudioInput

// MARK: - AppState

@Test @MainActor func appStateInitialStatus() {
    let state = AppState()
    #expect(state.status == .idle)
    #expect(state.audioLevel == 0.0)
}

@Test @MainActor func appStateStatusRecording() {
    let state = AppState()
    state.status = .recording(.insert)
    #expect(state.status == .recording(.insert))

    state.status = .recording(.dvn)
    #expect(state.status == .recording(.dvn))
}

@Test @MainActor func appStateStatusTranscribing() {
    let state = AppState()
    state.status = .transcribing(.insert)
    #expect(state.status == .transcribing(.insert))

    state.status = .transcribing(.dvn)
    #expect(state.status == .transcribing(.dvn))
}

@Test @MainActor func appStateStatusEquality() {
    #expect(AppState.Status.idle == .idle)
    #expect(AppState.Status.error == .error)
    #expect(AppState.Status.recording(.insert) == .recording(.insert))
    #expect(AppState.Status.recording(.insert) != .recording(.dvn))
    #expect(AppState.Status.recording(.insert) != .transcribing(.insert))
}

@Test @MainActor func appStateAudioLevel() {
    let state = AppState()
    state.audioLevel = 0.5
    #expect(state.audioLevel == 0.5)
    state.audioLevel = 0.0
    #expect(state.audioLevel == 0.0)
}

// MARK: - AppSettings overlayEnabled

@Test func appSettingsOverlayEnabledDefault() {
    let settings = AppSettings()
    #expect(settings.overlayEnabled == true)
}

@Test func appSettingsOverlayEnabledCodableRoundTrip() throws {
    var settings = AppSettings()
    settings.overlayEnabled = false

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    #expect(decoded.overlayEnabled == false)
}

@Test func appSettingsOverlayEnabledDefaultWhenKeyMissing() throws {
    // overlayEnabled キーを含まない旧スキーマの JSON でも既定値 true で復元できる。
    // カスタム init(from:) が decodeIfPresent ?? true でフォールバックするため、
    // 既存ユーザーの設定全体がリセットされない。
    var dict = try JSONSerialization.jsonObject(
        with: JSONEncoder().encode(AppSettings())) as! [String: Any]
    dict.removeValue(forKey: "overlayEnabled")
    let data = try JSONSerialization.data(withJSONObject: dict)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
    #expect(decoded.overlayEnabled == true)
    #expect(decoded.notesDirPath == "~/audio")
    #expect(decoded.fillerFilterEnabled == true)
}
