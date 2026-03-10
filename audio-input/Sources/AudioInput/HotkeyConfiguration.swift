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
        let normalized = Self.normalize(modifierFlags)
        if isModifierOnly {
            guard let expected = KeyCode.expectedFlag(for: keyCode) else {
                preconditionFailure(
                    "modifier-only configuration requires a modifier key code, got \(keyCode)"
                )
            }
            precondition(
                normalized == expected,
                "modifierFlags (\(modifierFlags.rawValue)) must match the modifier key's flag (\(expected.rawValue))"
            )
        } else {
            precondition(
                !KeyCode.modifierKeyCodes.contains(keyCode),
                "key combo configuration must not use a modifier key code (\(keyCode)); use isModifierOnly: true instead"
            )
            precondition(
                normalized.rawValue != 0,
                "key combo configuration requires at least one modifier (Shift/Control/Option/Command)"
            )
        }
        self.keyCode = keyCode
        self.modifierFlagsRawValue = normalized.rawValue
        self.isModifierOnly = isModifierOnly
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let rawValue = try container.decode(UInt64.self, forKey: .modifierFlagsRawValue)
        let isModifierOnly = try container.decode(Bool.self, forKey: .isModifierOnly)
        if isModifierOnly {
            guard let expected = KeyCode.expectedFlag(for: keyCode) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription:
                            "modifier-only configuration requires a modifier key code, got \(keyCode)"
                    )
                )
            }
            guard Self.normalize(CGEventFlags(rawValue: rawValue)) == expected else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription:
                            "modifierFlags (\(rawValue)) must match the modifier key's flag (\(expected.rawValue))"
                    )
                )
            }
        } else {
            guard !KeyCode.modifierKeyCodes.contains(keyCode) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription:
                            "key combo configuration must not use a modifier key code (\(keyCode)); use isModifierOnly: true instead"
                    )
                )
            }
            let normalized = Self.normalize(CGEventFlags(rawValue: rawValue))
            guard normalized.rawValue != 0 else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: container.codingPath,
                        debugDescription:
                            "key combo configuration requires at least one modifier (Shift/Control/Option/Command)"
                    )
                )
            }
        }
        self.keyCode = keyCode
        // 正規化して保存（CapsLock/Fn/device bits を除外）
        self.modifierFlagsRawValue = Self.normalize(CGEventFlags(rawValue: rawValue)).rawValue
        self.isModifierOnly = isModifierOnly
    }

    /// CGEventFlags に変換する。
    public var modifierFlags: CGEventFlags {
        CGEventFlags(rawValue: modifierFlagsRawValue)
    }

    /// Shift/Control/Option/Command の 4 種だけを抽出するマスク。
    /// CapsLock, Fn, device-specific bits 等を除外し、
    /// 設定値と event.flags の比較を一貫させる。
    public static let relevantModifierMask = CGEventFlags(
        rawValue:
            CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskControl.rawValue
            | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskCommand.rawValue
    )

    /// modifierFlags を relevantModifierMask で正規化する。
    private static func normalize(_ flags: CGEventFlags) -> CGEventFlags {
        CGEventFlags(rawValue: flags.rawValue & relevantModifierMask.rawValue)
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

        /// modifier keyCode に対応する CGEventFlags を返す。
        /// keyCode と modifierFlags の整合性検証に使用。
        public static func expectedFlag(for keyCode: UInt16) -> CGEventFlags? {
            switch keyCode {
            case rightOption, leftOption: return .maskAlternate
            case rightShift, leftShift: return .maskShift
            case rightControl, leftControl: return .maskControl
            case rightCommand, leftCommand: return .maskCommand
            default: return nil
            }
        }

        /// modifier keyCode に対応する device-specific CGEventFlags を返す。
        /// IOKit/IOLLEvent.h の NX_DEVICE*KEYMASK 定数。
        /// 右/左修飾キーを正確に区別するために使用する。
        public static func deviceFlag(for keyCode: UInt16) -> CGEventFlags? {
            switch keyCode {
            case rightOption: return CGEventFlags(rawValue: 0x00000040)   // NX_DEVICERALTKEYMASK
            case leftOption: return CGEventFlags(rawValue: 0x00000020)    // NX_DEVICELALTKEYMASK
            case rightShift: return CGEventFlags(rawValue: 0x00000004)    // NX_DEVICERSHIFTKEYMASK
            case leftShift: return CGEventFlags(rawValue: 0x00000002)     // NX_DEVICELSHIFTKEYMASK
            case rightControl: return CGEventFlags(rawValue: 0x00002000)  // NX_DEVICERCTLKEYMASK
            case leftControl: return CGEventFlags(rawValue: 0x00000001)   // NX_DEVICELCTLKEYMASK
            case rightCommand: return CGEventFlags(rawValue: 0x00000010)  // NX_DEVICERCMDKEYMASK
            case leftCommand: return CGEventFlags(rawValue: 0x00000008)   // NX_DEVICELCMDKEYMASK
            default: return nil
            }
        }
    }
}
