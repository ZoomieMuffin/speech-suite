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

    @Test("decoding valid modifier-only config succeeds")
    func decodingValidModifierOnly() throws {
        // isModifierOnly=true で keyCode が修飾キー → 正常に decode
        let json = """
            {"keyCode":61,"modifierFlagsRawValue":524288,"isModifierOnly":true}
            """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(HotkeyConfiguration.self, from: data)
        #expect(config == HotkeyConfiguration.rightOption)
    }
}
