import Foundation

struct PortableConfiguration: Equatable, Sendable, Codable {
    static let schemaVersion = 1
    static let maximumBytes = 2 * 1_024 * 1_024
    let value: ConfigurationValue

    init(value: ConfigurationValue) throws {
        guard case .number(let version) = value["schemaVersion"], version.rounded() == version,
            version >= 1, version <= Double(Int32.max)
        else {
            throw ConfigurationError.invalid(
                "Folder sync requires a positive schemaVersion. For a backup snapshot, import the original "
                    + ".tinycast archive in Backup, then initialize an empty configuration folder.")
        }
        guard version == Double(Self.schemaVersion) else {
            throw ConfigurationError.incompatible(Int(version))
        }
        self.value = try Self.rule.validate(value, at: "settings.json")
        try ConfigurationValidation.validate(self)
    }

    init(data: Data) throws {
        guard data.count <= Self.maximumBytes else {
            throw ConfigurationError.invalid("settings.json exceeds 2 MiB.")
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw ConfigurationError.invalid("settings.json must be UTF-8 JSON.")
        }
        try ConfigurationJSON.validateStructure(data)
        try self.init(value: JSONDecoder().decode(ConfigurationValue.self, from: data))
    }

    init(from decoder: Decoder) throws { try self.init(value: ConfigurationValue(from: decoder)) }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
    func encoded() throws -> Data { try value.encoded() }
    subscript(_ key: String) -> ConfigurationValue { value[key] }

    static var rule: ConfigurationRule {
        .fields(
            [
                "schemaVersion": .integers([1]),
                "settings": .fields(
                    ConfigurationCoverage.settingsRules, defaults: ConfigurationCoverage.defaults),
                "customCommands": .map(command), "customCommandOrder": .list(.text),
                "quicklinks": .map(quicklink), "pinnedQuicklinks": .list(.text),
                "windowLayouts": .map(layout), "hotkeys": .map(binding),
                "favoriteApps": .list(.text), "hiddenLauncherItems": .map(.choice([.bool(true)])),
                "hiddenLauncherKinds": .map(.choice([.bool(true)])), "launcherAliases": .map(.text)
            ],
            defaults: [
                "settings": .object([:]), "customCommands": .object([:]), "customCommandOrder": .array([]),
                "quicklinks": .object([:]), "pinnedQuicklinks": .array([]), "windowLayouts": .object([:]),
                "hotkeys": .object([:]), "favoriteApps": .array([]), "hiddenLauncherItems": .object([:]),
                "hiddenLauncherKinds": .object([:]), "launcherAliases": .object([:])
            ])
    }

    private static var command: ConfigurationRule {
        .fields(
            [
                "name": .text, "command": .text, "isEnabled": .flag, "loadsShellEnvironment": .flag,
                "requiresConfirmation": .flag, "showsConfirmation": .flag, "showsOutput": .flag,
                "arguments": .list(
                    .fields(["name": .text, "isOptional": .flag], defaults: ["isOptional": .bool(false)])),
                "workingDirectory": .optional(.text), "iconSymbol": .optional(.text)
            ],
            defaults: [
                "isEnabled": .bool(true), "loadsShellEnvironment": .bool(false),
                "requiresConfirmation": .bool(false),
                "showsConfirmation": .bool(false), "showsOutput": .bool(false), "arguments": .array([]),
                "workingDirectory": .null, "iconSymbol": .null
            ])
    }

    private static var quicklink: ConfigurationRule {
        .fields(
            [
                "name": .text, "link": .text, "openWithBundleID": .optional(.text),
                "iconSymbol": .optional(.text),
                "isEnabled": .flag, "showsInRootSearch": .flag
            ],
            defaults: [
                "openWithBundleID": .null, "iconSymbol": .null, "isEnabled": .bool(true),
                "showsInRootSearch": .bool(true)
            ])
    }

    private static var layout: ConfigurationRule {
        .fields(
            [
                "name": .text, "iconSymbol": .optional(.text), "usesPreferredGap": .flag,
                "entries": .map(
                    .fields(
                        [
                            "bundleID": .text, "argument": .optional(.text),
                            "displayRole": .strings(["primary", "secondary", "tertiary"]),
                            "widthFraction": .number(0...1, integer: false),
                            "heightFraction": .number(0...1, integer: false),
                            "anchor": .strings([
                                "top-left", "top", "top-right", "left", "center", "right",
                                "bottom-left", "bottom", "bottom-right"
                            ]),
                            "offsetX": .number(-10_000...10_000, integer: false),
                            "offsetY": .number(-10_000...10_000, integer: false)
                        ],
                        defaults: [
                            "argument": .null, "displayRole": .string("primary"),
                            "widthFraction": .number(1), "heightFraction": .number(1),
                            "anchor": .string("center"), "offsetX": .number(0), "offsetY": .number(0)
                        ])), "entryOrder": .list(.text)
            ], defaults: ["iconSymbol": .null, "usesPreferredGap": .bool(true)])
    }

    private static var binding: ConfigurationRule {
        .fields(
            [
                "keyCode": .optional(.number(0...127, integer: true)),
                "modifiers": .optional(.number(0...6_912, integer: true)),
                "doubleTap": .optional(.strings(["control", "option", "shift", "command"]))
            ], defaults: ["keyCode": .null, "modifiers": .null, "doubleTap": .null])
    }
}
