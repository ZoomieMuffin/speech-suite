import Foundation
import SpeechCore

/// Insert モードと Daily Voice Note モードの 2 つのホットキーを管理し、
/// それぞれの UseCase に配線するオーケストレーター。
///
/// **設定の反映タイミング**: ホットキー設定・notesDir・フィルタ設定は `init` 時に
/// `SettingsStore` からスナップショットとして読み込む。実行中の設定変更を反映するには
/// `AppController` を再生成する必要がある。設定 UI 追加時に対応予定。
@MainActor
public final class AppController {
    private let insertManager: HotkeyManager
    private let dvnManager: HotkeyManager
    private let insertUseCase: InsertTranscriptionUseCase
    private let dvnUseCase: AppendDailyVoiceNoteUseCase
    private let notificationService: NotificationService

    /// 現在アクティブなモード。Insert / DVN の同時使用を防ぐ排他制御に使う。
    /// recorder と transcriptionService は両 UseCase で共有しているため、
    /// 重ね押しで両方が start() を叩くと競合が発生する。
    private enum ActiveMode { case insert, dvn }
    private var activeMode: ActiveMode?

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
    /// 通知権限をホットキー登録より先に要求することで、起動直後の登録失敗通知が
    /// 権限未取得（isAuthorized == false）で握り潰されるのを防ぐ。
    public func start() async {
        await notificationService.requestAuthorization()

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
        switch event {
        case .pressed:
            guard activeMode == nil else { return }  // DVN がアクティブなら無視
            activeMode = .insert
            do { try await insertUseCase.start() } catch {
                activeMode = nil
                notificationService.notifyError(error, context: "テキスト挿入エラー")
            }
        case .released:
            guard activeMode == .insert else { return }
            // activeMode は stop() 完了後にクリアする。
            // 先にクリアすると stop() の await 中に別モードの pressed が通り、
            // recorder / transcriptionService が stop() と start() で競合する。
            do { try await insertUseCase.stop() } catch {
                notificationService.notifyError(error, context: "テキスト挿入エラー")
            }
            activeMode = nil
        }
    }

    private func handleDVN(_ event: HotkeyEvent) async {
        switch event {
        case .pressed:
            guard activeMode == nil else { return }  // Insert がアクティブなら無視
            activeMode = .dvn
            do { try await dvnUseCase.start() } catch {
                activeMode = nil
                notificationService.notifyError(error, context: "Voice Note 保存エラー")
            }
        case .released:
            guard activeMode == .dvn else { return }
            do { try await dvnUseCase.stop() } catch {
                notificationService.notifyError(error, context: "Voice Note 保存エラー")
            }
            activeMode = nil
        }
    }
}
