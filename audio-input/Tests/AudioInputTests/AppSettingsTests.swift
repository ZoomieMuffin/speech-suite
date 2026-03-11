import Foundation
import Testing
@testable import AudioInput

// MARK: - AppSettings

@Test func appSettingsDefaultValues() {
    let settings = AppSettings()
    #expect(settings.notesDirPath == "~/audio")
    #expect(settings.fillerFilterEnabled == true)
    #expect(settings.fillerPatterns.isEmpty)
}

@Test func appSettingsCodableRoundTrip() throws {
    var settings = AppSettings()
    settings.notesDirPath = "/tmp/notes"
    settings.fillerFilterEnabled = false
    settings.fillerPatterns = ["えーと", "あのー"]

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

    #expect(decoded.notesDirPath == "/tmp/notes")
    #expect(decoded.fillerFilterEnabled == false)
    #expect(decoded.fillerPatterns == ["えーと", "あのー"])
}

@Test func appSettingsNotesDirURLExpandsTilde() {
    var settings = AppSettings()
    settings.notesDirPath = "~/audio"
    let url = settings.notesDirURL
    #expect(url.path.hasPrefix("/"))
    #expect(!url.path.contains("~"))
    #expect(url.path.hasSuffix("audio"))
}

@Test func appSettingsNotesDirURLAbsolutePath() {
    var settings = AppSettings()
    settings.notesDirPath = "/tmp/voice-notes"
    #expect(settings.notesDirURL.path == "/tmp/voice-notes")
}

@Test func appSettingsDefaultHotkeys() {
    let settings = AppSettings()
    #expect(settings.insertHotkey == .rightOption)
    #expect(settings.dailyVoiceNoteHotkey == .shiftControlF)
}
