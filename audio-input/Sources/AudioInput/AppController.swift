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
    private let appState: AppState
    private let overlayController: OverlayWindowController
    /// オーバーレイ表示設定。init 時のスナップショット。設定 UI 追加時に live-update 対応予定。
    private let overlayEnabled: Bool

    /// 現在アクティブなモード。Insert / DVN の同時使用を防ぐ排他制御に使う。
    /// recorder と transcriptionService は両 UseCase で共有しているため、
    /// 重ね押しで両方が start() を叩くと競合が発生する。
    private enum ActiveMode { case insert, dvn }
    private var activeMode: ActiveMode?

    /// ホットキー登録失敗フラグ。start() で一度でも失敗すると true になる。
    /// updateStatus(.idle) 時に .error に留めることで、片方のホットキーが壊れた事実を保持する。
    private var hasRegistrationError = false

    public init(
        settingsStore: SettingsStore,
        notificationService: NotificationService,
        appState: AppState,
        overlayController: OverlayWindowController,
        recorder: any AudioRecorderProtocol,
        transcriptionService: any TranscriptionService,
        inserter: any TextInserterProtocol
    ) throws {
        let settings = settingsStore.settings
        self.notificationService = notificationService
        self.appState = appState
        self.overlayController = overlayController
        self.overlayEnabled = settings.overlayEnabled

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
        let textProcessor: (any TextProcessorProtocol)? = settings.fillerFilterEnabled
            ? FillerTextProcessor(customPatterns: settings.fillerPatterns)
            : nil
        self.dvnUseCase = AppendDailyVoiceNoteUseCase(
            recorder: recorder,
            transcriptionService: transcriptionService,
            textProcessor: textProcessor,
            sink: sink,
            hallucinationFilter: fillerFilter
        )
    }

    /// ホットキー監視を開始する。エラーはシステム通知で表示する。
    /// 通知権限をホットキー登録より先に要求することで、起動直後の登録失敗通知が
    /// 権限未取得（isAuthorized == false）で握り潰されるのを防ぐ。
    /// いずれかのホットキー登録に失敗した場合は appState.status を .error に設定し、
    /// メニューバーアイコンでユーザーに知らせる。
    public func start() async {
        hasRegistrationError = false
        await notificationService.requestAuthorization()

        do {
            try await insertManager.start { [weak self] event in
                await self?.handleInsert(event)
            }
        } catch {
            hasRegistrationError = true
            notificationService.notifyError(error, context: "Insert ホットキー")
        }

        do {
            try await dvnManager.start { [weak self] event in
                await self?.handleDVN(event)
            }
        } catch {
            hasRegistrationError = true
            notificationService.notifyError(error, context: "Voice Note ホットキー")
        }

        if hasRegistrationError {
            updateStatus(.error)
        }
    }

    /// ホットキー監視を停止する。
    /// 録音中の場合は UseCase を先に停止して確定処理を完了させてからホットキーを解除する。
    /// これを省くと録音中データが消失し、recorder / transcriptionService が解放されない。
    public func stop() async {
        switch activeMode {
        case .insert:
            updateStatus(.transcribing(.insert))
            do { try await insertUseCase.stop() } catch {
                notificationService.notifyError(error, context: "テキスト挿入エラー")
            }
            activeMode = nil
            updateStatus(.idle)
        case .dvn:
            updateStatus(.transcribing(.dvn))
            do { try await dvnUseCase.stop() } catch {
                notificationService.notifyError(error, context: "Voice Note 保存エラー")
            }
            activeMode = nil
            updateStatus(.idle)
        case nil:
            break
        }
        await insertManager.stop()
        await dvnManager.stop()
    }

    // MARK: - Private

    /// appState.status を更新し、状態に応じてオーバーレイを表示/非表示にする。
    /// SwiftUI View のライフサイクルに依存せず、常に正しく動作する。
    ///
    /// - オーバーレイは .recording 中のみ表示する。.transcribing でキーを離した時点で
    ///   即座に消えるため、「離すと消える」仕様と一致する。
    /// - .idle に戻る際、登録失敗がある場合は .error を維持する。
    ///   片方のホットキーが壊れた状態でも正常フローに上書きされない。
    private func updateStatus(_ status: AppState.Status) {
        let effective: AppState.Status
        if case .idle = status, hasRegistrationError {
            effective = .error
        } else {
            effective = status
        }
        appState.status = effective
        // 録音終了・文字起こし移行時にレベルをリセットして残像を防ぐ。
        // PRV-72 で実測値が入っても次回表示直後に前回値が残らない。
        switch effective {
        case .transcribing, .idle, .error:
            appState.audioLevel = 0.0
        case .recording:
            break
        }
        switch effective {
        case .recording:
            if overlayEnabled {
                overlayController.show(appState: appState)
            }
        case .transcribing, .idle, .error:
            overlayController.hide()
        }
    }

    private func handleInsert(_ event: HotkeyEvent) async {
        switch event {
        case .pressed:
            guard activeMode == nil else { return }  // DVN がアクティブなら無視
            activeMode = .insert
            updateStatus(.recording(.insert))
            do { try await insertUseCase.start() } catch {
                activeMode = nil
                updateStatus(.idle)
                notificationService.notifyError(error, context: "テキスト挿入エラー")
            }
        case .released:
            guard activeMode == .insert else { return }
            // activeMode は stop() 完了後にクリアする。
            // 先にクリアすると stop() の await 中に別モードの pressed が通り、
            // recorder / transcriptionService が stop() と start() で競合する。
            updateStatus(.transcribing(.insert))
            do { try await insertUseCase.stop() } catch {
                notificationService.notifyError(error, context: "テキスト挿入エラー")
            }
            activeMode = nil
            updateStatus(.idle)
        }
    }

    private func handleDVN(_ event: HotkeyEvent) async {
        switch event {
        case .pressed:
            guard activeMode == nil else { return }  // Insert がアクティブなら無視
            activeMode = .dvn
            updateStatus(.recording(.dvn))
            do { try await dvnUseCase.start() } catch {
                activeMode = nil
                updateStatus(.idle)
                notificationService.notifyError(error, context: "Voice Note 保存エラー")
            }
        case .released:
            guard activeMode == .dvn else { return }
            updateStatus(.transcribing(.dvn))
            do {
                let didSave = try await dvnUseCase.stop()
                if didSave {
                    notificationService.notifySuccess("Voice Note を保存しました")
                }
            } catch {
                notificationService.notifyError(error, context: "Voice Note 保存エラー")
            }
            activeMode = nil
            updateStatus(.idle)
        }
    }
}
