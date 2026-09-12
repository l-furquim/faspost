import AppKit
import SwiftUI

struct Keybinding: Equatable, Codable, Hashable {
    var key: String
    var modifiers: Int

    static let none = Keybinding(key: "", modifiers: 0)

    var isAssigned: Bool { !key.isEmpty }

    var eventModifiers: EventModifiers {
        EventModifiers(rawValue: modifiers)
    }

    var keyEquivalent: KeyEquivalent? {
        switch key {
        case "":
            nil
        case "return":
            .return
        case "delete":
            .delete
        case "escape":
            .escape
        case "space":
            .space
        case "tab":
            .tab
        default:
            key.first.map { KeyEquivalent($0) }
        }
    }

    var keyboardShortcut: KeyboardShortcut? {
        guard let keyEquivalent else { return nil }
        return KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    var glyphs: String? {
        guard isAssigned else { return nil }
        return ShortcutGlyphs.string(key: key, modifiers: eventModifiers)
    }

    init(key: String, modifiers: Int) {
        self.key = key
        self.modifiers = modifiers
    }

    init(key: String, modifiers: EventModifiers) {
        self.key = key
        self.modifiers = modifiers.rawValue
    }

    init?(event: NSEvent) {
        var modifiers = EventModifiers()
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }

        let key: String
        switch event.keyCode {
        case 36, 76:
            key = "return"
        case 51, 117:
            key = "delete"
        case 53:
            key = "escape"
        case 48:
            key = "tab"
        case 49:
            key = "space"
        default:
            guard let character = event.charactersIgnoringModifiers?.lowercased().first,
                  character.isLetter || character.isNumber
            else { return nil }
            key = String(character)
        }
        self.init(key: key, modifiers: modifiers)
    }

    static let reserved: Set<Keybinding> = [
        Keybinding(key: "c", modifiers: .command),
        Keybinding(key: "v", modifiers: .command),
        Keybinding(key: "x", modifiers: .command),
        Keybinding(key: "a", modifiers: .command),
        Keybinding(key: "z", modifiers: .command),
        Keybinding(key: "q", modifiers: .command),
    ]
}

enum ShortcutGlyphs {
    static func string(key: String, modifiers: EventModifiers) -> String {
        var glyphs = ""
        if modifiers.contains(.control) { glyphs += "⌃" }
        if modifiers.contains(.option) { glyphs += "⌥" }
        if modifiers.contains(.shift) { glyphs += "⇧" }
        if modifiers.contains(.command) { glyphs += "⌘" }
        switch key {
        case "return": glyphs += "↩"
        case "delete": glyphs += "⌫"
        case "escape": glyphs += "⎋"
        case "space": glyphs += "Space"
        case "tab": glyphs += "⇥"
        default: glyphs += key.uppercased()
        }
        return glyphs
    }
}

enum KeybindingStorage {
    static let overrides = "shortcuts.overrides"
}

@Observable
final class KeybindingStore {
    private var overrides: [String: Keybinding] = [:]
    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func binding(for id: AppCommandID) -> Keybinding? {
        if let stored = overrides[id.rawValue] {
            return stored.isAssigned ? stored : nil
        }
        return AppCommandCatalog[id].defaultBinding
    }

    func isCustomized(_ id: AppCommandID) -> Bool {
        overrides[id.rawValue] != nil
    }

    func glyphs(for id: AppCommandID) -> String? {
        binding(for: id)?.glyphs
    }

    func keyboardShortcut(for id: AppCommandID) -> KeyboardShortcut? {
        binding(for: id)?.keyboardShortcut
    }

    @discardableResult
    func set(_ newBinding: Keybinding, for id: AppCommandID) -> Bool {
        guard newBinding.isAssigned else { return false }
        if Keybinding.reserved.contains(newBinding) {
            return false
        }

        for other in AppCommandID.allCases where other != id {
            guard binding(for: other) == newBinding else { continue }
            if AppCommandCatalog[other].defaultBinding == newBinding {
                overrides[other.rawValue] = Keybinding.none
            } else {
                overrides.removeValue(forKey: other.rawValue)
            }
        }

        if newBinding == AppCommandCatalog[id].defaultBinding {
            overrides.removeValue(forKey: id.rawValue)
        } else {
            overrides[id.rawValue] = newBinding
        }
        persist()
        return true
    }

    func reset(_ id: AppCommandID) {
        overrides.removeValue(forKey: id.rawValue)
        persist()
    }

    func resetAll() {
        overrides = [:]
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: KeybindingStorage.overrides),
              let decoded = try? JSONDecoder().decode([String: Keybinding].self, from: data)
        else { return }
        overrides = decoded
    }

    private func persist() {
        if overrides.isEmpty {
            defaults.removeObject(forKey: KeybindingStorage.overrides)
            return
        }
        defaults.set(try? JSONEncoder().encode(overrides), forKey: KeybindingStorage.overrides)
    }
}

extension KeybindingStore {
    static var preview: KeybindingStore {
        let suite = "fastpost.preview.shortcuts"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return KeybindingStore(defaults: defaults)
    }
}
