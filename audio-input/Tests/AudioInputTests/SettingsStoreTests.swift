import Foundation
import Testing
@testable import AudioInput

// MARK: - SettingsStore
//
// SettingsStore は UserDefaults.standard に固定キーで保存するため、
// テスト間の干渉を防ぐために .serialized で直列化する。
// 各テスト前後にキーを削除してサンドボックス化する。

@Suite(.serialized)
@MainActor
struct SettingsStoreTests {
    // SettingsStore.userDefaultsKey を直接参照することで、キー変更時にテスト側も追従する。
    private let settingsKey = SettingsStore.userDefaultsKey

    @Test func defaultsWhenNoPriorData() {
        UserDefaults.standard.removeObject(forKey: settingsKey)
        defer { UserDefaults.standard.removeObject(forKey: settingsKey) }

        let store = SettingsStore()
        #expect(store.settings.notesDirPath == "~/audio")
        #expect(store.settings.fillerFilterEnabled == true)
        #expect(store.settings.fillerPatterns.isEmpty)
        #expect(store.settings.overlayEnabled == true)
    }

    @Test func updatePersistsAcrossInit() {
        UserDefaults.standard.removeObject(forKey: settingsKey)
        defer { UserDefaults.standard.removeObject(forKey: settingsKey) }

        let store = SettingsStore()
        store.update { $0.notesDirPath = "/tmp/test-notes" }

        let store2 = SettingsStore()
        #expect(store2.settings.notesDirPath == "/tmp/test-notes")
    }

    @Test func updateMultipleFields() {
        UserDefaults.standard.removeObject(forKey: settingsKey)
        defer { UserDefaults.standard.removeObject(forKey: settingsKey) }

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

    @Test func updateReflectsImmediately() {
        UserDefaults.standard.removeObject(forKey: settingsKey)
        defer { UserDefaults.standard.removeObject(forKey: settingsKey) }

        let store = SettingsStore()
        #expect(store.settings.overlayEnabled == true)

        store.update { $0.overlayEnabled = false }
        #expect(store.settings.overlayEnabled == false)

        store.update { $0.overlayEnabled = true }
        #expect(store.settings.overlayEnabled == true)
    }

    @Test func overlayEnabledPersists() {
        UserDefaults.standard.removeObject(forKey: settingsKey)
        defer { UserDefaults.standard.removeObject(forKey: settingsKey) }

        let store = SettingsStore()
        store.update { $0.overlayEnabled = false }

        let store2 = SettingsStore()
        #expect(store2.settings.overlayEnabled == false)
    }
}
