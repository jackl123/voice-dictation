import Carbon.HIToolbox
import CoreGraphics
import AppKit

/// Stores the user's chosen hotkey combination in UserDefaults.
/// Defaults to Option+Space (⌥Space).
///
/// Supports three kinds of hotkey:
/// 1. **Modifier + key** — e.g. ⌥Space, ⌘⇧D  (keyCode != -1, isModifierOnly == false)
/// 2. **Modifier-only**  — e.g. Right ⌘, fn/🌐  (keyCode == modifier key code, isModifierOnly == true)
/// 3. **Function key**   — e.g. F5               (keyCode == kVK_F5, no modifiers)
struct HotKeyConfiguration: Codable, Equatable {

    /// Virtual key code (e.g. `kVK_Space`, `kVK_ANSI_D`).
    /// For modifier-only hotkeys this holds the modifier's own key code
    /// (e.g. `kVK_RightCommand`, `kVK_Function`).
    var keyCode: Int

    /// Raw value of `CGEventFlags` representing the modifier keys.
    var modifierFlags: UInt64

    /// When `true`, the hotkey fires on pressing/releasing a modifier key alone
    /// (no accompanying letter/number key).
    var isModifierOnly: Bool

    // Default initialiser for backwards compatibility with existing persisted data
    // that doesn't include `isModifierOnly`.
    init(keyCode: Int, modifierFlags: UInt64, isModifierOnly: Bool = false) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.isModifierOnly = isModifierOnly
    }

    // MARK: - Presets

    static let `default` = optionSpace

    static let optionSpace = HotKeyConfiguration(
        keyCode: Int(kVK_Space),
        modifierFlags: CGEventFlags.maskAlternate.rawValue
    )

    static let rightCommand = HotKeyConfiguration(
        keyCode: Int(kVK_RightCommand),
        modifierFlags: CGEventFlags.maskCommand.rawValue,
        isModifierOnly: true
    )

    static let fnKey = HotKeyConfiguration(
        keyCode: Int(kVK_Function),
        modifierFlags: CGEventFlags.maskSecondaryFn.rawValue,
        isModifierOnly: true
    )

    static let controlSpace = HotKeyConfiguration(
        keyCode: Int(kVK_Space),
        modifierFlags: CGEventFlags.maskControl.rawValue
    )

    static let commandShiftSpace = HotKeyConfiguration(
        keyCode: Int(kVK_Space),
        modifierFlags: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue
    )

    static let f5 = HotKeyConfiguration(
        keyCode: Int(kVK_F5),
        modifierFlags: 0
    )

    /// All built-in presets for the dropdown menu.
    struct Preset: Identifiable {
        let id: String
        let label: String
        let config: HotKeyConfiguration
    }

    static let presets: [Preset] = [
        Preset(id: "option_space",    label: "\u{2325}Space (Option + Space)",          config: .optionSpace),
        Preset(id: "fn",              label: "\u{1F310} fn (Globe key)",                config: .fnKey),
        Preset(id: "right_cmd",       label: "Right \u{2318} (Right Command)",          config: .rightCommand),
        Preset(id: "ctrl_space",      label: "\u{2303}Space (Control + Space)",         config: .controlSpace),
        Preset(id: "cmd_shift_space", label: "\u{2318}\u{21E7}Space (Cmd+Shift+Space)", config: .commandShiftSpace),
        Preset(id: "f5",              label: "F5",                                      config: .f5),
        Preset(id: "custom",          label: "Custom...",                                config: .default),  // placeholder
    ]

    /// Returns the preset ID that matches this configuration, or "custom" if none match.
    var matchingPresetID: String {
        for preset in Self.presets where preset.id != "custom" {
            if preset.config == self { return preset.id }
        }
        return "custom"
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "hotkeyConfiguration"

    /// Loads the saved configuration, or returns the default.
    static func load() -> HotKeyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: Self.userDefaultsKey),
              let config = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data)
        else {
            return .default
        }
        return config
    }

    /// Saves the configuration to UserDefaults.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    // MARK: - Matching

    /// The CGEventFlags built from the stored raw value (only modifier bits).
    var cgEventFlags: CGEventFlags {
        CGEventFlags(rawValue: modifierFlags)
    }

    /// Required modifier masks that must all be present.
    var requiredModifiers: [CGEventFlags] {
        var result: [CGEventFlags] = []
        if cgEventFlags.contains(.maskAlternate)   { result.append(.maskAlternate) }
        if cgEventFlags.contains(.maskCommand)     { result.append(.maskCommand) }
        if cgEventFlags.contains(.maskControl)     { result.append(.maskControl) }
        if cgEventFlags.contains(.maskShift)       { result.append(.maskShift) }
        if cgEventFlags.contains(.maskSecondaryFn) { result.append(.maskSecondaryFn) }
        return result
    }

    /// Modifier masks that must NOT be present (excludes fn since it's often
    /// set alongside other keys on laptop keyboards).
    var excludedModifiers: [CGEventFlags] {
        let all: [CGEventFlags] = [.maskAlternate, .maskCommand, .maskControl, .maskShift]
        return all.filter { !cgEventFlags.contains($0) }
    }

    /// Returns `true` if the given CGEvent matches this hotkey configuration
    /// for a regular (non-modifier-only) hotkey.
    func matches(keyCode eventKeyCode: Int64, flags: CGEventFlags) -> Bool {
        guard !isModifierOnly else { return false }
        guard Int(eventKeyCode) == keyCode else { return false }
        for mod in requiredModifiers {
            guard flags.contains(mod) else { return false }
        }
        for mod in excludedModifiers {
            if flags.contains(mod) { return false }
        }
        return true
    }

    /// Returns `true` if the given flagsChanged event represents this
    /// modifier-only hotkey being pressed (modifier became active).
    func matchesModifierDown(keyCode eventKeyCode: Int64, flags: CGEventFlags) -> Bool {
        guard isModifierOnly else { return false }
        guard Int(eventKeyCode) == keyCode else { return false }
        // The modifier flag should now be present.
        for mod in requiredModifiers {
            guard flags.contains(mod) else { return false }
        }
        return true
    }

    /// Returns `true` if the given flagsChanged event represents this
    /// modifier-only hotkey being released (modifier became inactive).
    func matchesModifierUp(keyCode eventKeyCode: Int64, flags: CGEventFlags) -> Bool {
        guard isModifierOnly else { return false }
        guard Int(eventKeyCode) == keyCode else { return false }
        // The modifier flag should now be absent.
        for mod in requiredModifiers {
            if flags.contains(mod) { return false }
        }
        return true
    }

    // MARK: - Display

    /// Human-readable label for the hotkey, e.g. "⌥Space", "⌘⇧D", "Right ⌘", "fn".
    var displayString: String {
        let kc = Int(keyCode)
        if isModifierOnly {
            if kc == Int(kVK_Function)     { return "fn" }
            if kc == Int(kVK_RightCommand) { return "Right \u{2318}" }
            if kc == Int(kVK_RightOption)  { return "Right \u{2325}" }
            if kc == Int(kVK_RightControl) { return "Right \u{2303}" }
            if kc == Int(kVK_RightShift)   { return "Right \u{21E7}" }
            if kc == Int(kVK_Command)      { return "Left \u{2318}" }
            if kc == Int(kVK_Option)       { return "Left \u{2325}" }
            if kc == Int(kVK_Control)      { return "Left \u{2303}" }
            if kc == Int(kVK_Shift)        { return "Left \u{21E7}" }
            return "Modifier"
        }

        var parts: [String] = []
        if cgEventFlags.contains(.maskControl)    { parts.append("\u{2303}") }  // ⌃
        if cgEventFlags.contains(.maskAlternate)   { parts.append("\u{2325}") } // ⌥
        if cgEventFlags.contains(.maskShift)       { parts.append("\u{21E7}") } // ⇧
        if cgEventFlags.contains(.maskCommand)     { parts.append("\u{2318}") } // ⌘
        parts.append(keyName)
        return parts.joined()
    }

    /// Name of the key for display purposes.
    var keyName: String {
        let kc = Int(keyCode)
        if kc == Int(kVK_Space)        { return "Space" }
        if kc == Int(kVK_Return)       { return "Return" }
        if kc == Int(kVK_Tab)          { return "Tab" }
        if kc == Int(kVK_Delete)       { return "Delete" }
        if kc == Int(kVK_Escape)       { return "Esc" }
        if kc == Int(kVK_F1)           { return "F1" }
        if kc == Int(kVK_F2)           { return "F2" }
        if kc == Int(kVK_F3)           { return "F3" }
        if kc == Int(kVK_F4)           { return "F4" }
        if kc == Int(kVK_F5)           { return "F5" }
        if kc == Int(kVK_F6)           { return "F6" }
        if kc == Int(kVK_F7)           { return "F7" }
        if kc == Int(kVK_F8)           { return "F8" }
        if kc == Int(kVK_F9)           { return "F9" }
        if kc == Int(kVK_F10)          { return "F10" }
        if kc == Int(kVK_F11)          { return "F11" }
        if kc == Int(kVK_F12)          { return "F12" }
        if kc == Int(kVK_UpArrow)      { return "\u{2191}" }
        if kc == Int(kVK_DownArrow)    { return "\u{2193}" }
        if kc == Int(kVK_LeftArrow)    { return "\u{2190}" }
        if kc == Int(kVK_RightArrow)   { return "\u{2192}" }
        if kc == Int(kVK_ANSI_A)       { return "A" }
        if kc == Int(kVK_ANSI_B)       { return "B" }
        if kc == Int(kVK_ANSI_C)       { return "C" }
        if kc == Int(kVK_ANSI_D)       { return "D" }
        if kc == Int(kVK_ANSI_E)       { return "E" }
        if kc == Int(kVK_ANSI_F)       { return "F" }
        if kc == Int(kVK_ANSI_G)       { return "G" }
        if kc == Int(kVK_ANSI_H)       { return "H" }
        if kc == Int(kVK_ANSI_I)       { return "I" }
        if kc == Int(kVK_ANSI_J)       { return "J" }
        if kc == Int(kVK_ANSI_K)       { return "K" }
        if kc == Int(kVK_ANSI_L)       { return "L" }
        if kc == Int(kVK_ANSI_M)       { return "M" }
        if kc == Int(kVK_ANSI_N)       { return "N" }
        if kc == Int(kVK_ANSI_O)       { return "O" }
        if kc == Int(kVK_ANSI_P)       { return "P" }
        if kc == Int(kVK_ANSI_Q)       { return "Q" }
        if kc == Int(kVK_ANSI_R)       { return "R" }
        if kc == Int(kVK_ANSI_S)       { return "S" }
        if kc == Int(kVK_ANSI_T)       { return "T" }
        if kc == Int(kVK_ANSI_U)       { return "U" }
        if kc == Int(kVK_ANSI_V)       { return "V" }
        if kc == Int(kVK_ANSI_W)       { return "W" }
        if kc == Int(kVK_ANSI_X)       { return "X" }
        if kc == Int(kVK_ANSI_Y)       { return "Y" }
        if kc == Int(kVK_ANSI_Z)       { return "Z" }
        if kc == Int(kVK_ANSI_0)       { return "0" }
        if kc == Int(kVK_ANSI_1)       { return "1" }
        if kc == Int(kVK_ANSI_2)       { return "2" }
        if kc == Int(kVK_ANSI_3)       { return "3" }
        if kc == Int(kVK_ANSI_4)       { return "4" }
        if kc == Int(kVK_ANSI_5)       { return "5" }
        if kc == Int(kVK_ANSI_6)       { return "6" }
        if kc == Int(kVK_ANSI_7)       { return "7" }
        if kc == Int(kVK_ANSI_8)       { return "8" }
        if kc == Int(kVK_ANSI_9)       { return "9" }
        if kc == Int(kVK_ANSI_Minus)   { return "-" }
        if kc == Int(kVK_ANSI_Equal)   { return "=" }
        if kc == Int(kVK_ANSI_LeftBracket)  { return "[" }
        if kc == Int(kVK_ANSI_RightBracket) { return "]" }
        if kc == Int(kVK_ANSI_Backslash)    { return "\\" }
        if kc == Int(kVK_ANSI_Semicolon)    { return ";" }
        if kc == Int(kVK_ANSI_Quote)        { return "'" }
        if kc == Int(kVK_ANSI_Comma)        { return "," }
        if kc == Int(kVK_ANSI_Period)       { return "." }
        if kc == Int(kVK_ANSI_Slash)        { return "/" }
        if kc == Int(kVK_ANSI_Grave)        { return "`" }
        if let char = Self.characterForKeyCode(keyCode) {
            return char.uppercased()
        }
        return "Key\(keyCode)"
    }

    /// Uses TIS to look up the character for an arbitrary key code.
    private static func characterForKeyCode(_ code: Int) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataPtr, to: CFData.self) as Data
        return layoutData.withUnsafeBytes { rawPtr -> String? in
            guard let basePtr = rawPtr.baseAddress else { return nil }
            let layoutPtr = basePtr.assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeyState: UInt32 = 0
            var length: Int = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layoutPtr,
                UInt16(code),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}
