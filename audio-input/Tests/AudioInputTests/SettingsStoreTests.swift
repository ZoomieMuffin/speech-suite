import Foundation
import Testing
@testable import AudioInput

// MARK: - SettingsStore
//
// SettingsStore は UserDefaults.standard に固定キーで保存するため、
// テスト前後にキーを削除してサンドボックス化する。

private let kSettingsKey = "com.speech-suite.AppSettings"

@Test @MainActor func settingsStoreReturnsDefaultsWhenNoPriorData() {
    UserDefaults.standard.removeObject(forKey: kSettingsKey)
    defer { UserDefaults.standard.removeObject(forKey: kSettingsKey) }

    let store = SettingsStore()
    #expect(store.settings.notesDirPath == "~/audio")
    #expect(store.settings.fillerFilterEnabled == true)
    #expect(store.settings.fillerPatterns.isEmpty)
    #expect(store.settings.overlayEnabled == true)
}

@Test @MainActor func settingsStoreUpdatePersistsAcrossInit() {
    UserDefaults.standard.removeObject(forKey: kSettingsKey)
    defer { UserDefaults.standard.removeObject(forKey: kSettingsKey) }

    let store = SettingsStore()
    store.update { $0.notesDirPath = "/tmp/test-notes" }

    let store2 = SettingsStore()
    #expect(store2.settings.notesDirPath == "/tmp/test-notes")
}

@Test @MainActor func settingsStoreUpdateMultipleFields() {
    UserDefaults.standard.removeObject(forKey: kSettingsKey)
    defer { UserDefaults.standard.removeObject(forKey: kSettingsKey) }

    let store = SettingsStore()
    store.update {
        $0.notesDirPath = "/tmp/notes"
        $0.fillerFilterEnabled = false
        $0.fillerPatterns = ["えーと", "あのー"]
        $0.overlayEnabled = false
    }

    #expect(store.settings.notesDirPath == "/tmp/notes")
    #expect(store.settings.fillerFilterEnabled == false)
    #expect(store.settings.fillerPatterns == ["えーと", "あのー"])
    #expect(store.settings.overlayEnabled == false)
}

@Test @MainActor func settingsStoreUpdateReflectsImmediately() {
    UserDefaults.standard.removeObject(forKey: kSettingsKey)
    defer { UserDefaults.standard.removeObject(forKey: kSettingsKey) }

    let store = SettingsStore()
    #expect(store.settings.overlayEnabled == true)

    store.update { $0.overlayEnabled = false }
    #expect(store.settings.overlayEnabled == false)

    store.update { $0.overlayEnabled = true }
    #expect(store.settings.overlayEnabled == true)
}

@Test @MainActor func settingsStoreOverlayEnabledPersists() {
    UserDefaults.standard.removeObject(forKey: kSettingsKey)
    defer { UserDefaults.standard.removeObject(forKey: kSettingsKey) }

    let store = SettingsStore()
    store.update { $0.overlayEnabled = false }

    let store2 = SettingsStore()
    #expect(store2.settings.overlayEnabled == false)
}
