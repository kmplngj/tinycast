import AppKit

@MainActor
final class ConfigurationRuntimeAdapter {
    private unowned let core: AppCore

    init(core: AppCore) { self.core = core }

    func gather() throws -> PortableConfiguration {
        var commands: [String: ConfigurationValue] = [:]
        for command in core.customCommands.commands {
            var value = try ConfigurationValue.encoding(command).object
            value.removeValue(forKey: "id")
            commands[command.id.uuidString.lowercased()] = .object(value)
        }
        var quicklinks: [String: ConfigurationValue] = [:]
        for quicklink in core.quicklinks.quicklinks {
            var value = try ConfigurationValue.encoding(quicklink).object
            for key in ["id", "createdAt", "pinnedAt"] { value.removeValue(forKey: key) }
            quicklinks[quicklink.id.uuidString.lowercased()] = .object(value)
        }
        var layouts: [String: ConfigurationValue] = [:]
        for layout in core.windowLayouts.layouts {
            layouts[layout.id.uuidString.lowercased()] = layoutValue(layout)
        }
        var bindings: [String: ConfigurationValue] = [:]
        for (action, binding) in core.hotKeys.allBindings {
            if let key = Self.key(action) { bindings[key] = Self.bindingValue(binding) }
        }
        let portable = ConfigurationValidation.portableEntry
        let kinds = Set([
            "application", "systemSettings", "command", "customCommand",
            "systemAction", "windowCommand", "windowLayout", "quicklink"
        ])
        return try PortableConfiguration(
            value: .object([
                "schemaVersion": .number(1), "settings": ConfigurationSettingsAdapter.gather(core.settings),
                "customCommands": .object(commands),
                "customCommandOrder": ids(core.customCommands.commands.map(\.id)),
                "quicklinks": .object(quicklinks),
                "pinnedQuicklinks": ids(
                    core.quicklinks.quicklinks.filter(\.isPinned).sorted(by: Quicklink.precedes).map(\.id)),
                "windowLayouts": .object(layouts), "hotkeys": .object(bindings),
                "favoriteApps": .array(core.favorites.keys.filter(portable).map(ConfigurationValue.string)),
                "hiddenLauncherItems": .object(
                    core.visibility.hiddenItemKeys.filter(portable).reduce(into: [:]) { $0[$1] = .bool(true) }
                ),
                "hiddenLauncherKinds": .object(
                    core.visibility.disabledKinds.filter { kinds.contains($0) }
                        .reduce(into: [:]) { $0[$1] = .bool(true) }),
                "launcherAliases": .object(
                    core.aliases.aliases.filter { portable($0.key) }.mapValues(ConfigurationValue.string))
            ]))
    }

    func validateProjection(_ document: PortableConfiguration) throws {
        guard core.quicklinks.isAvailable else { throw QuicklinkError.storageUnavailable }
        for section in ["customCommands", "quicklinks", "windowLayouts"] {
            let names = document[section].object.values.map {
                $0["name"].string.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive], locale: .current)
            }
            guard Set(names).count == names.count else {
                throw ConfigurationError.invalid("Duplicate names in this Mac’s locale: " + section)
            }
        }
    }

    func apply(_ document: PortableConfiguration) throws {
        try validateProjection(document)
        let commands: [CustomCommand] = try document["customCommandOrder"].array.map {
            var value = document["customCommands"][$0.string].object
            value["id"] = $0
            return try ConfigurationValue.object(value).decoded(CustomCommand.self)
        }
        let quicklinks: [Quicklink] = try document["quicklinks"].object.sorted { $0.key < $1.key }.map { id, record in
            var value = record.object
            value["id"] = .string(id)
            let previous = core.quicklinks.quicklinks.first { $0.id.uuidString.lowercased() == id }
            value["createdAt"] = .number(previous?.createdAt.timeIntervalSinceReferenceDate ?? 0)
            if let pin = document["pinnedQuicklinks"].array.firstIndex(of: .string(id)) {
                value["pinnedAt"] = .number(Double(pin))
            }
            guard QuicklinkDestination.detect(record["link"].string) != nil else {
                throw QuicklinkError.unresolvableLink
            }
            return try ConfigurationValue.object(value).decoded(Quicklink.self)
        }
        let layouts = try document["windowLayouts"].object.map { try layout(id: $0.key, value: $0.value) }
        var bindings: [HotKeyAction: HotKeyBinding] = [:]
        for (key, value) in document["hotkeys"].object {
            if let action = Self.action(key) { bindings[action] = Self.binding(value) }
        }
        for (action, binding) in core.hotKeys.allBindings where Self.key(action) == nil {
            guard !bindings.values.contains(binding) else {
                throw ConfigurationError.invalid(
                    "A portable shortcut conflicts with a local extension shortcut.")
            }
        }
        if core.quicklinks.quicklinks != quicklinks.sorted(by: Quicklink.precedes) {
            try core.quicklinkCoordinator.replaceConfigurationQuicklinks(quicklinks)
        }
        for action in core.hotKeys.allBindings.keys where Self.key(action) != nil {
            core.hotKeys.setBinding(nil, for: action)
        }
        core.customCommandCoordinator.replaceCustomCommands(commands)
        core.windowLayoutCoordinator.replaceWindowLayouts(layouts)
        ConfigurationSettingsAdapter.apply(document["settings"], to: core.settings)
        for (action, binding) in bindings { core.hotKeys.setBinding(binding, for: action) }
        let portable = ConfigurationValidation.portableEntry
        let localFavorites = core.favorites.keys.filter { !portable($0) }
        core.favorites.replace(keys: document["favoriteApps"].array.map(\.string) + localFavorites)
        let localItems = core.visibility.hiddenItemKeys.filter { !portable($0) }
        let localKinds = core.visibility.disabledKinds.filter {
            ["snippet", "extensionCommand", "meeting", "quickAction", "appleShortcut"].contains($0)
        }
        core.visibility.replace(
            hiddenItems: Array(document["hiddenLauncherItems"].object.keys) + localItems,
            disabledKinds: Array(document["hiddenLauncherKinds"].object.keys) + localKinds)
        let aliases = document["launcherAliases"].object.mapValues(\.string)
        core.aliases.replace(
            core.aliases.aliases.filter { !portable($0.key) }.merging(aliases) { _, new in new })
    }

    static func key(_ action: HotKeyAction) -> String? {
        switch action {
        case .togglePalette: "togglePalette"
        case .command(let id): id.rawValue
        case .app(let id): "app:" + id
        case .settingsPane(let id): "pane:" + id
        case .customCommand(let id): "custom-command:" + id.uuidString.lowercased()
        case .systemAction(let id): "system-action:" + id.rawValue
        case .windowCommand(let id): "window-command:" + id.rawValue
        case .windowLayout(let id): "window-layout:" + id.uuidString.lowercased()
        case .quicklink(let id): "quicklink:" + id.uuidString.lowercased()
        case .extensionCommand, .quickAction, .customWindowSize, .appleShortcut: nil
        }
    }

    static func action(_ key: String) -> HotKeyAction? {
        if key == "togglePalette" { return .togglePalette }
        guard let colon = key.firstIndex(of: ":") else { return nil }
        let prefix = String(key[..<colon])
        let id = String(key[key.index(after: colon)...])
        switch prefix {
        case "command": return CommandID(rawValue: key)?.hotKeyAction
        case "app": return .app(bundleID: id)
        case "pane": return .settingsPane(bundleID: id)
        case "custom-command": return UUID(uuidString: id).map { .customCommand(id: $0) }
        case "system-action": return SystemAction.ID(rawValue: id).map { .systemAction(id: $0) }
        case "window-command": return WindowCommand.ID(rawValue: id).map { .windowCommand(id: $0) }
        case "window-layout": return UUID(uuidString: id).map { .windowLayout(id: $0) }
        case "quicklink": return UUID(uuidString: id).map { .quicklink(id: $0) }
        default: return nil
        }
    }

    func refreshAvailability() { core.hotKeys.refreshRegistrations() }

    private static func bindingValue(_ value: HotKeyBinding) -> ConfigurationValue {
        switch value {
        case .combo(let shortcut):
            .object([
                "keyCode": .number(Double(shortcut.carbonKeyCode)),
                "modifiers": .number(Double(shortcut.carbonModifiers))
            ])
        case .doubleTap(let modifier): .object(["doubleTap": .string(modifier.rawValue)])
        }
    }

    private static func binding(_ value: ConfigurationValue) -> HotKeyBinding {
        if case .string(let modifier) = value["doubleTap"],
            let modifier = DoubleTapModifier(rawValue: modifier)
        {
            return .doubleTap(modifier)
        }
        return .combo(
            KeyShortcut(
                carbonKeyCode: Int(value["keyCode"].number), carbonModifiers: Int(value["modifiers"].number)))
    }

    private func ids(_ ids: [UUID]) -> ConfigurationValue {
        .array(ids.map { .string($0.uuidString.lowercased()) })
    }

    private func layoutValue(_ layout: WindowLayout) -> ConfigurationValue {
        let screens = NSScreen.screens
        let primary = screens.first.flatMap(AXScreens.uuid(of:))
        let others = AXScreens.layoutScreens(geometry: AXGeometry(screens: screens))
            .map(\.display.uuid).filter { $0 != primary }
        let displays = [primary].compactMap { $0 } + others
        var entries: [String: ConfigurationValue] = [:]
        for entry in layout.entries {
            let role: String
            if entry.display.uuid.hasPrefix("role:") {
                role = String(entry.display.uuid.dropFirst(5))
            } else {
                role =
                    ["primary", "secondary", "tertiary"][
                        min(displays.firstIndex(of: entry.display.uuid) ?? 0, 2)]
            }
            entries[entry.id.uuidString.lowercased()] = .object([
                "bundleID": .string(entry.bundleID),
                "argument": entry.argument.map(ConfigurationValue.string) ?? .null,
                "displayRole": .string(role), "widthFraction": .number(entry.widthFraction),
                "heightFraction": .number(entry.heightFraction), "anchor": .string(entry.anchor.rawValue),
                "offsetX": .number(entry.offset.x), "offsetY": .number(entry.offset.y)
            ])
        }
        return .object([
            "name": .string(layout.name),
            "iconSymbol": layout.iconSymbol.map(ConfigurationValue.string) ?? .null,
            "usesPreferredGap": .bool(layout.usesPreferredGap), "entries": .object(entries),
            "entryOrder": ids(layout.entries.map(\.id))
        ])
    }

    private func layout(id: String, value: ConfigurationValue) throws -> WindowLayout {
        let entries = try value["entryOrder"].array.map { key -> WindowLayoutEntry in
            let record = value["entries"][key.string]
            guard let id = UUID(uuidString: key.string),
                let anchor = WindowLayoutAnchor(rawValue: record["anchor"].string)
            else {
                throw ConfigurationError.invalid("Invalid layout entry.")
            }
            return WindowLayoutEntry(
                id: id, bundleID: record["bundleID"].string,
                argument: record["argument"] == .null ? nil : record["argument"].string,
                display: WindowLayoutDisplay(
                    uuid: "role:" + record["displayRole"].string,
                    name: record["displayRole"].string.capitalized),
                widthFraction: record["widthFraction"].number,
                heightFraction: record["heightFraction"].number,
                anchor: anchor, offset: CGPoint(x: record["offsetX"].number, y: record["offsetY"].number))
        }
        guard let uuid = UUID(uuidString: id) else { throw ConfigurationError.invalid("Invalid layout ID.") }
        return WindowLayout(
            id: uuid, name: value["name"].string,
            iconSymbol: value["iconSymbol"] == .null ? nil : value["iconSymbol"].string,
            usesPreferredGap: value["usesPreferredGap"].bool, entries: entries,
            frontmostEntryID: core.windowLayouts.layout(id: uuid)?.frontmostEntryID.flatMap { marked in
                entries.contains { $0.id == marked } ? marked : nil
            },
            createdAt: core.windowLayouts.layout(id: uuid)?.createdAt
                ?? Date(timeIntervalSinceReferenceDate: 0))
    }
}
