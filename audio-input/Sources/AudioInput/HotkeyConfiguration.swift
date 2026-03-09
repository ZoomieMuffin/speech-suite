import CoreGraphics

/// ホットキーの設定を表すモデル。
/// modifier-only（右 Option 単体）と通常キーコンボ（Shift+Ctrl+F 等）の両方を扱う。
public struct HotkeyConfiguration: Sendable, Equatable, Codable {
    /// 仮想キーコード（Carbon kVK_* 相当）
    public let keyCode: UInt16
    /// 必要な修飾キーフラグ（CGEventFlags の rawValue）
    public let modifierFlagsRawValue: UInt64
    /// true の場合、修飾キー単体の押下/離しで発火する
    public let isModifierOnly: Bool

    public init(keyCode: UInt16, modifierFlags: CGEventFlags, isModifierOnly: Bool) {
        precondition(
            !isModifierOnly || KeyCode.modifierKeyCodes.contains(keyCode),
            "modifier-only configuration requires a modifier key code"
        )
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlags.rawValue
        self.isModifierOnly = isModifierOnly
    }

    /// CGEventFlags に変換する。
    public var modifierFlags: CGEventFlags {
        CGEventFlags(rawValue: modifierFlagsRawValue)
    }
}

// MARK: - Presets

extension HotkeyConfiguration {
    /// 右 Option ホールド（Insert モードの既定）
    public static let rightOption = HotkeyConfiguration(
        keyCode: KeyCode.rightOption,
        modifierFlags: .maskAlternate,
        isModifierOnly: true
    )

    /// Shift + Ctrl + F ホールド（Daily Voice Note モードの既定）
    public static let shiftControlF = HotkeyConfiguration(
        keyCode: KeyCode.ansiF,
        modifierFlags: CGEventFlags([.maskShift, .maskControl]),
        isModifierOnly: false
    )
}

// MARK: - Key Codes

extension HotkeyConfiguration {
    /// Carbon HIToolbox の仮想キーコード定数。
    /// Package 環境では Carbon をインポートできないため直接定義する。
    public enum KeyCode {
        public static let rightOption: UInt16 = 0x3D   // 61
        public static let leftOption: UInt16 = 0x3A    // 58
        public static let rightShift: UInt16 = 0x3C    // 60
        public static let leftShift: UInt16 = 0x38     // 56
        public static let rightControl: UInt16 = 0x3E  // 62
        public static let leftControl: UInt16 = 0x3B   // 59
        public static let rightCommand: UInt16 = 0x36  // 54
        public static let leftCommand: UInt16 = 0x37   // 55
        public static let ansiF: UInt16 = 0x03

        /// 全修飾キーコードの集合。isModifierOnly バリデーションに使用。
        public static let modifierKeyCodes: Set<UInt16> = [
            rightOption, leftOption,
            rightShift, leftShift,
            rightControl, leftControl,
            rightCommand, leftCommand,
        ]
    }
}
