import CoreGraphics
import Foundation
import Testing

@testable import AudioInput

@Suite("HotkeyConfiguration")
struct HotkeyConfigurationTests {

    // MARK: - Presets

    @Test("rightOption preset has correct values")
    func rightOptionPreset() {
        let config = HotkeyConfiguration.rightOption
        #expect(config.keyCode == HotkeyConfiguration.KeyCode.rightOption)
        #expect(config.keyCode == 0x3D)
        #expect(config.isModifierOnly == true)
        #expect(config.modifierFlags.contains(.maskAlternate))
    }

    @Test("shiftControlF preset has correct values")
    func shiftControlFPreset() {
        let config = HotkeyConfiguration.shiftControlF
        #expect(config.keyCode == HotkeyConfiguration.KeyCode.ansiF)
        #expect(config.keyCode == 0x03)
        #expect(config.isModifierOnly == false)
        #expect(config.modifierFlags.contains(.maskShift))
        #expect(config.modifierFlags.contains(.maskControl))
    }

    // MARK: - Custom Configuration

    @Test("custom configuration preserves values")
    func customConfiguration() {
        let config = HotkeyConfiguration(
            keyCode: HotkeyConfiguration.KeyCode.leftCommand,
            modifierFlags: .maskCommand,
            isModifierOnly: true
        )
        #expect(config.keyCode == 0x37)
        #expect(config.isModifierOnly == true)
        #expect(config.modifierFlags.contains(.maskCommand))
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves values")
    func codableRoundTrip() throws {
        let original = HotkeyConfiguration.rightOption
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable round-trip for key combo")
    func codableRoundTripKeyCombo() throws {
        let original = HotkeyConfiguration.shiftControlF
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable round-trip for custom configuration")
    func codableRoundTripCustom() throws {
        let original = HotkeyConfiguration(
            keyCode: 0x0E,  // kVK_ANSI_E
            modifierFlags: CGEventFlags([.maskCommand, .maskShift]),
            isModifierOnly: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Equatable

    @Test("same configurations are equal")
    func equality() {
        let a = HotkeyConfiguration.rightOption
        let b = HotkeyConfiguration(
            keyCode: 0x3D,
            modifierFlags: .maskAlternate,
            isModifierOnly: true
        )
        #expect(a == b)
    }

    @Test("different configurations are not equal")
    func inequality() {
        #expect(HotkeyConfiguration.rightOption != HotkeyConfiguration.shiftControlF)
    }

    // MARK: - Key Codes

    @Test("key codes match Carbon HIToolbox values")
    func keyCodes() {
        #expect(HotkeyConfiguration.KeyCode.rightOption == 0x3D)
        #expect(HotkeyConfiguration.KeyCode.leftOption == 0x3A)
        #expect(HotkeyConfiguration.KeyCode.rightShift == 0x3C)
        #expect(HotkeyConfiguration.KeyCode.leftShift == 0x38)
        #expect(HotkeyConfiguration.KeyCode.rightControl == 0x3E)
        #expect(HotkeyConfiguration.KeyCode.leftControl == 0x3B)
        #expect(HotkeyConfiguration.KeyCode.rightCommand == 0x36)
        #expect(HotkeyConfiguration.KeyCode.leftCommand == 0x37)
        #expect(HotkeyConfiguration.KeyCode.ansiF == 0x03)
    }

    @Test("right and left modifier key codes are distinct")
    func rightLeftDistinction() {
        #expect(HotkeyConfiguration.KeyCode.rightOption != HotkeyConfiguration.KeyCode.leftOption)
        #expect(HotkeyConfiguration.KeyCode.rightShift != HotkeyConfiguration.KeyCode.leftShift)
        #expect(HotkeyConfiguration.KeyCode.rightControl != HotkeyConfiguration.KeyCode.leftControl)
        #expect(HotkeyConfiguration.KeyCode.rightCommand != HotkeyConfiguration.KeyCode.leftCommand)
    }

    // MARK: - Validation

    @Test("modifierKeyCodes contains all 8 modifier keys")
    func modifierKeyCodesSet() {
        let codes = HotkeyConfiguration.KeyCode.modifierKeyCodes
        #expect(codes.count == 8)
        #expect(codes.contains(HotkeyConfiguration.KeyCode.rightOption))
        #expect(codes.contains(HotkeyConfiguration.KeyCode.leftOption))
        #expect(codes.contains(HotkeyConfiguration.KeyCode.rightShift))
        #expect(codes.contains(HotkeyConfiguration.KeyCode.leftShift))
        #expect(codes.contains(HotkeyConfiguration.KeyCode.rightControl))
        #expect(codes.contains(HotkeyConfiguration.KeyCode.leftControl))
        #expect(codes.contains(HotkeyConfiguration.KeyCode.rightCommand))
        #expect(codes.contains(HotkeyConfiguration.KeyCode.leftCommand))
    }

    @Test("non-modifier key is allowed when isModifierOnly is false")
    func nonModifierKeyAllowed() {
        let config = HotkeyConfiguration(
            keyCode: HotkeyConfiguration.KeyCode.ansiF,
            modifierFlags: .maskCommand,
            isModifierOnly: false
        )
        #expect(config.keyCode == HotkeyConfiguration.KeyCode.ansiF)
    }

    @Test("decoding invalid modifier-only config throws DecodingError")
    func decodingInvalidModifierOnly() throws {
        // isModifierOnly=true だが keyCode が通常キー → decode 時にエラー
        let json = """
            {"keyCode":3,"modifierFlagsRawValue":524288,"isModifierOnly":true}
            """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        }
    }

    @Test("decoding modifier-only with mismatched flag throws DecodingError")
    func decodingMismatchedFlag() throws {
        // keyCode=rightOption だが modifierFlags=.maskCommand → 不整合
        let json = """
            {"keyCode":61,"modifierFlagsRawValue":1048576,"isModifierOnly":true}
            """
        let data = Data(json.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        }
    }

    @Test("decoding valid modifier-only config succeeds")
    func decodingValidModifierOnly() throws {
        // isModifierOnly=true で keyCode が修飾キー + 正しいフラグ → 正常に decode
        let json = """
            {"keyCode":61,"modifierFlagsRawValue":524288,"isModifierOnly":true}
            """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        #expect(config == HotkeyConfiguration.rightOption)
    }

    // MARK: - expectedFlag mapping

    @Test("expectedFlag returns correct flag for each modifier pair")
    func expectedFlagMapping() {
        typealias KC = HotkeyConfiguration.KeyCode
        #expect(KC.expectedFlag(for: KC.rightOption) == .maskAlternate)
        #expect(KC.expectedFlag(for: KC.leftOption) == .maskAlternate)
        #expect(KC.expectedFlag(for: KC.rightShift) == .maskShift)
        #expect(KC.expectedFlag(for: KC.leftShift) == .maskShift)
        #expect(KC.expectedFlag(for: KC.rightControl) == .maskControl)
        #expect(KC.expectedFlag(for: KC.leftControl) == .maskControl)
        #expect(KC.expectedFlag(for: KC.rightCommand) == .maskCommand)
        #expect(KC.expectedFlag(for: KC.leftCommand) == .maskCommand)
    }

    @Test("expectedFlag returns nil for non-modifier key")
    func expectedFlagNil() {
        #expect(HotkeyConfiguration.KeyCode.expectedFlag(for: 0x03) == nil)
    }

    // MARK: - Device-specific flags

    @Test("deviceFlag returns distinct flags for right and left modifiers")
    func deviceFlagDistinction() {
        typealias KC = HotkeyConfiguration.KeyCode
        // 右と左で異なるフラグが返る
        #expect(KC.deviceFlag(for: KC.rightOption) != KC.deviceFlag(for: KC.leftOption))
        #expect(KC.deviceFlag(for: KC.rightShift) != KC.deviceFlag(for: KC.leftShift))
        #expect(KC.deviceFlag(for: KC.rightControl) != KC.deviceFlag(for: KC.leftControl))
        #expect(KC.deviceFlag(for: KC.rightCommand) != KC.deviceFlag(for: KC.leftCommand))
    }

    @Test("deviceFlag returns non-nil for all modifier keys")
    func deviceFlagNonNil() {
        for keyCode in HotkeyConfiguration.KeyCode.modifierKeyCodes {
            #expect(HotkeyConfiguration.KeyCode.deviceFlag(for: keyCode) != nil)
        }
    }

    @Test("deviceFlag returns nil for non-modifier key")
    func deviceFlagNil() {
        #expect(HotkeyConfiguration.KeyCode.deviceFlag(for: 0x03) == nil)
    }

    @Test("deviceFlag values match IOKit NX_DEVICE*KEYMASK constants")
    func deviceFlagValues() {
        typealias KC = HotkeyConfiguration.KeyCode
        #expect(KC.deviceFlag(for: KC.rightOption) == CGEventFlags(rawValue: 0x00000040))
        #expect(KC.deviceFlag(for: KC.leftOption) == CGEventFlags(rawValue: 0x00000020))
        #expect(KC.deviceFlag(for: KC.rightShift) == CGEventFlags(rawValue: 0x00000004))
        #expect(KC.deviceFlag(for: KC.leftShift) == CGEventFlags(rawValue: 0x00000002))
        #expect(KC.deviceFlag(for: KC.rightControl) == CGEventFlags(rawValue: 0x00002000))
        #expect(KC.deviceFlag(for: KC.leftControl) == CGEventFlags(rawValue: 0x00000001))
        #expect(KC.deviceFlag(for: KC.rightCommand) == CGEventFlags(rawValue: 0x00000010))
        #expect(KC.deviceFlag(for: KC.leftCommand) == CGEventFlags(rawValue: 0x00000008))
    }
}
