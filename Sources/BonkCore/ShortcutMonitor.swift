import AppKit
import Carbon.HIToolbox
import Foundation

/// The global shortcut that starts Bonk: a physical key, its modifiers and the key's label.
public struct Shortcut: Codable, Equatable {
    public let keyCode: UInt16
    /// Raw `NSEvent.ModifierFlags`, limited to ⌃⌥⇧⌘.
    public let modifiers: UInt
    /// The key's unmodified character, uppercased.
    public let label: String

    public static let defaultShortcut = Shortcut(keyCode: UInt16(kVK_ANSI_B), modifiers: [.shift, .command], label: "B")

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.control, .option, .shift, .command]).rawValue
        self.label = label.uppercased()
    }

    /// Migrates the old single-letter setting to ⇧⌘ plus that letter; anything else is ⇧⌘B.
    init(legacyLetter: String?) {
        guard let letter = legacyLetter?.uppercased(), let keyCode = Self.ansiLetterKeyCodes[letter] else {
            self = Self.defaultShortcut
            return
        }
        self.init(keyCode: UInt16(keyCode), modifiers: [.shift, .command], label: letter)
    }

    /// Builds a shortcut from a recorded key press, or throws why it is refused.
    public static func recorded(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) throws -> Shortcut {
        guard keyCode != UInt16(kVK_Escape) else { throw ShortcutRejection.escape }
        guard let characters, characters.count == 1,
              characters.unicodeScalars.allSatisfy(printableKeys.contains) else {
            throw ShortcutRejection.unsupportedKey
        }
        guard !modifiers.isDisjoint(with: [.command, .control]) else { throw ShortcutRejection.needsCommandOrControl }
        return Shortcut(keyCode: keyCode, modifiers: modifiers, label: characters)
    }

    public var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    public var displayString: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifierFlags.contains($0.0) }.map(\.1).joined() + label
    }

    var carbonModifiers: UInt32 {
        let pairs: [(NSEvent.ModifierFlags, Int)] = [(.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey)]
        return pairs.reduce(0) { result, pair in modifierFlags.contains(pair.0) ? result | UInt32(pair.1) : result }
    }

    private static let printableKeys = CharacterSet.letters
        .union(.decimalDigits)
        .union(.punctuationCharacters)
        .union(.symbols)

    private static let ansiLetterKeyCodes: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
        "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
        "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z
    ]
}

public enum ShortcutRejection: LocalizedError {
    case escape
    case unsupportedKey
    case needsCommandOrControl

    public var errorDescription: String? {
        switch self {
        case .escape: return "Escape is reserved for unlocking."
        case .unsupportedKey: return "Use a letter, number or punctuation key."
        case .needsCommandOrControl: return "Include ⌘ or ⌃."
        }
    }
}

/// Registers the shortcut as a Carbon hot key: it needs no permission and consumes the key.
@MainActor
public final class ShortcutMonitor {
    fileprivate var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var shortcut: Shortcut?

    public init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    /// Replaces the registered shortcut. Returns `noErr`, or the failing status with nothing registered.
    public func register(_ shortcut: Shortcut) -> OSStatus {
        if eventHandler == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                bonkHotKeyHandler,
                1,
                &pressed,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
            guard status == noErr else { return status }
        }

        unregisterHotKey()
        let id = EventHotKeyID(signature: 0x424F_4E4B, id: 1) // "BONK"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &ref
        )
        guard status == noErr else { return status }
        hotKey = ref
        self.shortcut = shortcut
        return noErr
    }

    /// Unregisters the hot key while the shortcut recorder listens; `resume()` restores it.
    public func suspend() {
        unregisterHotKey()
    }

    public func resume() {
        guard hotKey == nil, let shortcut else { return }
        _ = register(shortcut)
    }

    public func stop() {
        unregisterHotKey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
        shortcut = nil
    }

    private func unregisterHotKey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        hotKey = nil
    }
}

private func bonkHotKeyHandler(_: EventHandlerCallRef?, _: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<ShortcutMonitor>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in monitor.onPress?() }
    return noErr
}
