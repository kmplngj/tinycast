import Foundation

enum ConfigurationValidation {
    static func validate(_ document: PortableConfiguration) throws {
        for section in ["customCommands", "quicklinks", "windowLayouts"] {
            var names: Set<String> = []
            for (id, value) in document[section].object {
                try uuid(id)
                try nonblank(value["name"].string, at: section + "/" + id + "/name")
                let name = value["name"].string.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                guard names.insert(name).inserted else {
                    throw ConfigurationError.invalid("\(section): duplicate name.")
                }
            }
        }
        try ordered(
            document["customCommandOrder"], keys: document["customCommands"].object.keys, complete: true)
        try ordered(document["pinnedQuicklinks"], keys: document["quicklinks"].object.keys, complete: false)
        for (id, command) in document["customCommands"].object {
            try nonblank(command["command"].string, at: "customCommands/\(id)/command")
            for argument in command["arguments"].array {
                try nonblank(argument["name"].string, at: "argument name")
            }
        }
        for (_, quicklink) in document["quicklinks"].object {
            try nonblank(quicklink["link"].string, at: "quicklink destination")
            if case .string(let bundle) = quicklink["openWithBundleID"] { try bundleID(bundle) }
        }
        for (_, layout) in document["windowLayouts"].object {
            guard !layout["entries"].object.isEmpty else {
                throw ConfigurationError.invalid("A layout needs an entry.")
            }
            try ordered(layout["entryOrder"], keys: layout["entries"].object.keys, complete: true)
            for (id, entry) in layout["entries"].object {
                try uuid(id)
                try bundleID(entry["bundleID"].string)
            }
        }
        var bindings: [ConfigurationValue] = []
        for (key, binding) in document["hotkeys"].object {
            try bindingTarget(key, document: document)
            let doubleTap = binding["doubleTap"] != .null
            let combo = binding["keyCode"] != .null && binding["modifiers"] != .null
            guard doubleTap != combo,
                !doubleTap || (binding["keyCode"] == .null && binding["modifiers"] == .null)
            else { throw ConfigurationError.invalid("\(key): use a combo or a doubleTap, never both.") }
            if combo {
                let modifiers = Int(binding["modifiers"].number)
                guard modifiers & ~6_912 == 0 else {
                    throw ConfigurationError.invalid("\(key): invalid modifiers.")
                }
                let functionKeys: Set<Int> = [
                    122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                    103, 111, 105, 107, 113, 106, 64, 79, 80, 90
                ]
                guard modifiers & 6_400 != 0 || functionKeys.contains(Int(binding["keyCode"].number)) else {
                    throw ConfigurationError.invalid(
                        "\(key): use Command, Option or Control, or a function key.")
                }
            }
            guard !bindings.contains(binding) else {
                throw ConfigurationError.invalid("Shortcut collision at \(key).")
            }
            bindings.append(binding)
        }
        let favorites = document["favoriteApps"].array.map(\.string)
        guard Set(favorites).count == favorites.count else {
            throw ConfigurationError.invalid("Duplicate favorite.")
        }
        for key in favorites + Array(document["launcherAliases"].object.keys)
            + Array(document["hiddenLauncherItems"].object.keys)
        {
            guard portableEntry(key) else {
                throw ConfigurationError.invalid("\(key) is not a portable launcher identity.")
            }
            try reference(key, document: document)
        }
        for (_, alias) in document["launcherAliases"].object { try nonblank(alias.string, at: "alias") }
        let kinds: Set<String> = [
            "application", "systemSettings", "command", "customCommand",
            "systemAction", "windowCommand", "windowLayout", "quicklink"
        ]
        guard Set(document["hiddenLauncherKinds"].object.keys).isSubset(of: kinds) else {
            throw ConfigurationError.invalid("hiddenLauncherKinds contains a local-only or unknown category.")
        }
    }

    static func portableEntry(_ key: String) -> Bool {
        if key.contains(":") {
            return [
                "command:", "custom-command:", "system-action:", "window-command:", "window-layout:",
                "quicklink:"
            ]
            .contains { key.hasPrefix($0) && key.count > $0.count }
        }
        return isBundleID(key)
    }

    static func isBundleID(_ key: String) -> Bool {
        key.contains(".") && !key.contains("/") && !key.contains(":")
            && key.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
            }
    }

    private static func bundleID(_ key: String) throws {
        guard isBundleID(key) else { throw ConfigurationError.invalid("Invalid bundle ID: \(key).") }
    }

    private static func uuid(_ key: String) throws {
        guard let id = UUID(uuidString: key), id.uuidString.lowercased() == key else {
            throw ConfigurationError.invalid("Entity IDs must be canonical lowercase UUIDs: \(key).")
        }
    }

    private static func nonblank(_ text: String, at path: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigurationError.invalid("\(path) must not be blank.")
        }
    }

    private static func ordered(
        _ value: ConfigurationValue, keys: some Sequence<String>, complete: Bool
    ) throws {
        let ids = value.array.map(\.string)
        let available = Set(keys)
        guard ids.count == Set(ids).count, Set(ids).isSubset(of: available),
            !complete || Set(ids) == available
        else {
            throw ConfigurationError.invalid("An ordered list has duplicate, missing or dangling entity IDs.")
        }
    }

    private static func bindingTarget(_ key: String, document: PortableConfiguration) throws {
        if key == "togglePalette" { return }
        guard let colon = key.firstIndex(of: ":") else {
            throw ConfigurationError.invalid("Invalid binding target: \(key).")
        }
        let prefix = String(key[..<colon])
        let id = String(key[key.index(after: colon)...])
        if ["app", "pane"].contains(prefix) { try bundleID(id); return }
        guard
            ["command", "custom-command", "system-action", "window-command", "window-layout", "quicklink"]
                .contains(prefix),
            !id.isEmpty
        else { throw ConfigurationError.invalid("Unsupported binding namespace: \(key).") }
        try reference(key, document: document)
    }

    private static func reference(_ key: String, document: PortableConfiguration) throws {
        for (prefix, section) in [
            ("custom-command:", "customCommands"), ("quicklink:", "quicklinks"),
            ("window-layout:", "windowLayouts")
        ] where key.hasPrefix(prefix) {
            guard document[section].object[String(key.dropFirst(prefix.count))] != nil else {
                throw ConfigurationError.invalid(
                    "Dangling reference: \(key). Remove the reference with its entity.")
            }
        }
    }
}
