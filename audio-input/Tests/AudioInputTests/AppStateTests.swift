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

// Note: スキーマ変更で overlayEnabled キーが欠落した旧 JSON のデコードは失敗する。
// SettingsStore は try? で失敗を捕捉し AppSettings() のデフォルト値で起動するため、
// 旧環境からのアップデート後も overlayEnabled は既定値 true で動作する。
