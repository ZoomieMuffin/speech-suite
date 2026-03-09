import CoreGraphics
import Foundation

// MARK: - Error

/// HotkeyManager で発生するエラー。
public enum HotkeyError: Error, LocalizedError, Sendable {
    /// CGEventTap の作成に失敗。アクセシビリティ権限が必要。
    case accessibilityPermissionDenied

    public var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required. Enable it in System Settings > Privacy & Security > Accessibility."
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
/// - コールバック内で `dispatchPrecondition` により実行時にもメインスレッドを検証する。
/// - したがって、可変プロパティ `isKeyDown` へのアクセスは常にメインスレッドに限定され、
///   データ競合は発生しない。
private final class EventTapState: @unchecked Sendable {
    let configuration: HotkeyConfiguration
    let handler: @Sendable (HotkeyEvent) -> Void
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    var isKeyDown = false

    /// `install()` 時に `passRetained` で確保した自身への参照。
    /// `uninstall()` で明示的に `release()` してバランスを取る。
    private var retainedSelf: Unmanaged<EventTapState>?

    init(
        configuration: HotkeyConfiguration,
        handler: @escaping @Sendable (HotkeyEvent) -> Void
    ) {
        self.configuration = configuration
        self.handler = handler
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
            // タップ作成失敗時は即座に retain を解放
            retained.release()
            throw HotkeyError.accessibilityPermissionDenied
        }

        self.retainedSelf = retained
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
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
    dispatchPrecondition(condition: .onQueue(.main))

    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let state = Unmanaged<EventTapState>.fromOpaque(userInfo).takeUnretainedValue()

    // システムがタップを無効化した場合は再有効化する
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
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
/// `.flagsChanged` イベントのキーコードで右/左を区別し、トグルで pressed/released を判定する。
private func handleModifierOnly(state: EventTapState, type: CGEventType, event: CGEvent) {
    guard type == .flagsChanged else { return }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    guard keyCode == state.configuration.keyCode else { return }

    // .flagsChanged はキーごとに press/release で交互に発火する。
    // キーコードで対象キーを特定済みなのでトグルで判定できる。
    if !state.isKeyDown {
        state.isKeyDown = true
        state.handler(.pressed)
    } else {
        state.isKeyDown = false
        state.handler(.released)
    }
}

/// 通常キーコンボ（Shift+Ctrl+F 等）の処理。
/// `.keyDown`/`.keyUp` でキーの状態を、`.flagsChanged` で修飾キーの離しを検知する。
private func handleKeyCombo(state: EventTapState, type: CGEventType, event: CGEvent) {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

    switch type {
    case .keyDown:
        guard keyCode == state.configuration.keyCode,
            !state.isKeyDown,
            event.flags.contains(state.configuration.modifierFlags)
        else { return }
        state.isKeyDown = true
        state.handler(.pressed)

    case .keyUp:
        guard keyCode == state.configuration.keyCode, state.isKeyDown else { return }
        state.isKeyDown = false
        state.handler(.released)

    case .flagsChanged:
        // コンボ中に修飾キーが離された場合 → released として扱う
        guard state.isKeyDown,
            !event.flags.contains(state.configuration.modifierFlags)
        else { return }
        state.isKeyDown = false
        state.handler(.released)

    default:
        break
    }
}
