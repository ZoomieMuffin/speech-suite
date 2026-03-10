import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Error

/// HotkeyManager で発生するエラー。
public enum HotkeyError: Error, LocalizedError, Sendable {
    /// アクセシビリティ権限が付与されていない。
    case accessibilityPermissionDenied
    /// CGEventTap の作成に失敗（権限以外の原因）。
    case eventTapCreationFailed
    /// CFRunLoopSource の作成に失敗。
    case runLoopSourceCreationFailed

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required. Enable it in System Settings > Privacy & Security > Accessibility."
        case .eventTapCreationFailed:
            return "Failed to create CGEventTap."
        case .runLoopSourceCreationFailed:
            return "Failed to create CFRunLoopSource from CGEventTap."
        }
    }
}

// MARK: - HotkeyManager

/// CGEventTap を使ったグローバルホットキー監視の実装。
/// modifier-only（右 Option 単体）と通常キーコンボの両方を扱える。
@MainActor
public final class HotkeyManager: HotkeyManagerProtocol {
    private let configuration: HotkeyConfiguration
    private var tapState: EventTapState?
    private var isTransitioning = false

    public init(configuration: HotkeyConfiguration = .rightOption) {
        self.configuration = configuration
    }

    deinit {
        // deinit は @MainActor 隔離を継承しないため、
        // 非メインスレッドからの uninstall() によるデータ競合を防ぐ。
        let state = tapState
        if let state {
            DispatchQueue.main.async { state.uninstall() }
        }
    }

    public func start(handler: @escaping @Sendable (HotkeyEvent) -> Void) async throws {
        // await stop() は suspension point を含むため、再入を防ぐガードを設ける
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        // 既存のタップがあれば先にクリーンアップ
        tapState?.uninstall()
        tapState = nil

        let state = EventTapState(configuration: configuration, handler: handler)
        try state.install()
        self.tapState = state
    }

    public func stop() async {
        guard !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }

        tapState?.uninstall()
        tapState = nil
    }
}

// MARK: - EventTapState

/// CGEventTap のライフサイクルとコールバック状態を管理する内部クラス。
///
/// `@unchecked Sendable` の安全性保証:
/// - CGEventTap コールバックは `CFRunLoopGetMain()` に追加されるため、
///   必ずメインスレッドで呼び出される。
/// - `HotkeyManager` は `@MainActor` なので `install()`/`uninstall()` もメインスレッド上。
/// - コールバック内で `Thread.isMainThread` アサーションにより実行時にもメインスレッドを検証する。
/// - したがって、可変プロパティ `isKeyDown` へのアクセスは常にメインスレッドに限定され、
///   データ競合は発生しない。
///
/// handler 呼び出しは `DispatchQueue.main.async` 経由で行う。
/// CFRunLoop コールバックは Swift 6 的に MainActor executor 上とは限らないため、
/// `MainActor.assumeIsolated` は使用せず、明示的に main queue にディスパッチする。
private final class EventTapState: @unchecked Sendable {
    let configuration: HotkeyConfiguration
    let handler: @Sendable (HotkeyEvent) -> Void
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var isKeyDown = false

    /// modifier-only 時に右/左を正確に区別するための device-specific フラグ。
    /// install() 前に keyCode から解決し、コールバック内で毎回計算しないようにする。
    let deviceFlag: CGEventFlags?

    /// `install()` 時に `passRetained` で確保した自身への参照。
    /// `uninstall()` で明示的に `release()` してバランスを取る。
    private var retainedSelf: Unmanaged<EventTapState>?

    init(
        configuration: HotkeyConfiguration,
        handler: @escaping @Sendable (HotkeyEvent) -> Void
    ) {
        self.configuration = configuration
        self.handler = handler
        self.deviceFlag = configuration.isModifierOnly
            ? HotkeyConfiguration.KeyCode.deviceFlag(for: configuration.keyCode)
            : nil
    }

    func install() throws {
        var eventMask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue
        if !configuration.isModifierOnly {
            eventMask |= (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
        }

        // passRetained で self を保持し、CGEventTap が生きている間
        // EventTapState が解放されないことを保証する。
        let retained = Unmanaged.passRetained(self)
        let pointer = retained.toOpaque()

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: eventMask,
                callback: eventTapCallback,
                userInfo: pointer
            )
        else {
            retained.release()
            // AXIsProcessTrusted() で権限不足を判別
            if !AXIsProcessTrusted() {
                throw HotkeyError.accessibilityPermissionDenied
            }
            throw HotkeyError.eventTapCreationFailed
        }

        guard
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        else {
            CGEvent.tapEnable(tap: tap, enable: false)
            retained.release()
            throw HotkeyError.runLoopSourceCreationFailed
        }

        self.retainedSelf = retained
        self.eventTap = tap
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func uninstall() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isKeyDown = false

        // install() で passRetained した参照を解放する
        retainedSelf?.release()
        retainedSelf = nil
    }

    /// handler を DispatchQueue.main.async 経由で呼び出す。
    /// CFRunLoop コールバックは MainActor executor 上とは限らないため、
    /// 明示的に main queue にディスパッチして MainActor 安全性を保証する。
    func notify(_ event: HotkeyEvent) {
        let handler = self.handler
        DispatchQueue.main.async { handler(event) }
    }
}

// MARK: - CGEventTap Callback

/// CGEventTap のコールバック（C 関数ポインタ）。
/// CFRunLoopGetMain() に追加されるため、メインスレッドで呼び出される。
private func eventTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    assert(Thread.isMainThread, "CGEventTap callback must run on the main thread")

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let state = Unmanaged<EventTapState>.fromOpaque(userInfo).takeUnretainedValue()

    // システムがタップを無効化した場合は再有効化する。
    // 押下中に無効化された場合は .released を通知してから状態をリセットし、
    // 呼び出し側が「押されたまま」で取り残されないようにする。
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if state.isKeyDown {
            state.isKeyDown = false
            state.notify(.released)
        }
        if let tap = state.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    if state.configuration.isModifierOnly {
        handleModifierOnly(state: state, type: type, event: event)
    } else {
        handleKeyCombo(state: state, type: type, event: event)
    }

    return Unmanaged.passUnretained(event)
}

/// modifier-only ホットキーの処理。
/// device-specific フラグ（NX_DEVICE*KEYMASK）で右/左を正確に区別する。
/// 共有フラグ（.maskAlternate 等）ではなく per-key フラグを使うことで、
/// 左 Option 押下中に右 Option を離しても正しく .released が発火する。
private func handleModifierOnly(state: EventTapState, type: CGEventType, event: CGEvent) {
    guard type == .flagsChanged else { return }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == state.configuration.keyCode else { return }

    // device-specific フラグで対象キーの押下/離しを判定する。
    // これにより左右の同種修飾キーの同時押しでも正確に追跡できる。
    guard let deviceFlag = state.deviceFlag else { return }
    let isDown = event.flags.contains(deviceFlag)
    if isDown && !state.isKeyDown {
        state.isKeyDown = true
        state.notify(.pressed)
    } else if !isDown && state.isKeyDown {
        state.isKeyDown = false
        state.notify(.released)
    }
}

/// 通常キーコンボ（Shift+Ctrl+F 等）の処理。
/// `.keyDown`/`.keyUp` でキーの状態を、`.flagsChanged` で修飾キーの離しを検知する。
///
/// 起動判定（.keyDown）: exact match で余分な修飾キーでは発火しない。
/// 継続判定（.flagsChanged）: contains で必須修飾キーが維持されているかだけを見る。
/// これにより、ホールド中に余分な修飾キーを一瞬足して戻しても .released しない。
private func handleKeyCombo(state: EventTapState, type: CGEventType, event: CGEvent) {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

    switch type {
    case .keyDown:
        // 起動: exact match（余分な modifier があれば発火しない）
        guard keyCode == state.configuration.keyCode,
            !state.isKeyDown,
            activeModifiers(event.flags) == state.configuration.modifierFlags
        else { return }
        state.isKeyDown = true
        state.notify(.pressed)

    case .keyUp:
        guard keyCode == state.configuration.keyCode, state.isKeyDown else { return }
        state.isKeyDown = false
        state.notify(.released)

    case .flagsChanged:
        // 継続: 必須修飾キーが全て押されているかを contains で判定。
        // 余分な修飾キーが追加されても .released せず、
        // 必須修飾キーが 1 つでも離された場合のみ .released する。
        guard state.isKeyDown,
            !activeModifiers(event.flags).contains(state.configuration.modifierFlags)
        else { return }
        state.isKeyDown = false
        state.notify(.released)

    default:
        break
    }
}

/// event.flags から 4 種の修飾キービットだけを抽出する。
private func activeModifiers(_ flags: CGEventFlags) -> CGEventFlags {
    CGEventFlags(rawValue: flags.rawValue & HotkeyConfiguration.relevantModifierMask.rawValue)
}
