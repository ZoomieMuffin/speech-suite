import Foundation
import SpeechCore

/// Insert モードと Daily Voice Note モードの 2 つのホットキーを管理し、
/// それぞれの UseCase に配線するオーケストレーター。
@MainActor
public final class AppController {
    private let insertManager: HotkeyManager
    private let dvnManager: HotkeyManager
    private let insertUseCase: InsertTranscriptionUseCase
    private let dvnUseCase: AppendDailyVoiceNoteUseCase
    private let notificationService: NotificationService

    public init(
        settingsStore: SettingsStore,
        notificationService: NotificationService,
        recorder: any AudioRecorderProtocol,
        transcriptionService: any TranscriptionService,
        inserter: any TextInserterProtocol
    ) throws {
        let settings = settingsStore.settings
        self.notificationService = notificationService

        let fillerFilter = try settings.fillerFilterEnabled
            ? HallucinationFilter(customPatterns: settings.fillerPatterns)
            : nil

        self.insertManager = HotkeyManager(configuration: settings.insertHotkey)
        self.dvnManager = HotkeyManager(configuration: settings.dailyVoiceNoteHotkey)

        self.insertUseCase = InsertTranscriptionUseCase(
            recorder: recorder,
            transcriptionService: transcriptionService,
            inserter: inserter,
            hallucinationFilter: fillerFilter
        )

        let sink = FileDailyNoteSink(notesDir: settings.notesDirURL)
        self.dvnUseCase = AppendDailyVoiceNoteUseCase(
            recorder: recorder,
            transcriptionService: transcriptionService,
            sink: sink,
            hallucinationFilter: fillerFilter
        )
    }

    /// ホットキー監視を開始する。エラーはシステム通知で表示する。
    public func start() async {
        do {
            try await insertManager.start { [weak self] event in
                guard let self else { return }
                Task { @MainActor in await self.handleInsert(event) }
            }
        } catch {
            notificationService.notifyError(error, context: "Insert ホットキー")
        }

        do {
            try await dvnManager.start { [weak self] event in
                guard let self else { return }
                Task { @MainActor in await self.handleDVN(event) }
            }
        } catch {
            notificationService.notifyError(error, context: "Voice Note ホットキー")
        }
    }

    /// ホットキー監視を停止する。
    public func stop() async {
        await insertManager.stop()
        await dvnManager.stop()
    }

    // MARK: - Private

    private func handleInsert(_ event: HotkeyEvent) async {
        do {
            switch event {
            case .pressed: try await insertUseCase.start()
            case .released: try await insertUseCase.stop()
            }
        } catch {
            notificationService.notifyError(error, context: "テキスト挿入エラー")
        }
    }

    private func handleDVN(_ event: HotkeyEvent) async {
        do {
            switch event {
            case .pressed: try await dvnUseCase.start()
            case .released: try await dvnUseCase.stop()
            }
        } catch {
            notificationService.notifyError(error, context: "Voice Note 保存エラー")
        }
    }
}
