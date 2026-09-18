import Foundation

@main
struct ConfigurationTest {
    static func main() throws {
        let empty = try parse(#"{"schemaVersion":1}"#)
        expect(empty["settings"]["appearance"] == .string("system"), "schema defaults")
        expect(empty["hotkeys"] == .object([:]), "missing shortcuts unbind")
        expect(empty["settings"]["windowCycle"] == .string("off"), "window cycle default")
        for mode in ["off", "sizes", "displays"] {
            let value = try changing(empty, section: "settings", key: "windowCycle", value: .string(mode))
            try expect(PortableConfiguration(data: value.encoded()) == value, "window cycle round trip")
        }
        let encoded = try empty.encoded()
        expect(encoded.last == 10, "trailing newline")
        try expect(
            try parse(String(bytes: encoded, encoding: .utf8)!).encoded() == encoded,
            "deterministic round trip")
        try expect(
            try parse(#"{ "settings": {"appearance":"system"}, "schemaVersion":1 }"#) == empty,
            "semantic equality")
        expect(
            Set(ConfigurationCoverage.included).isDisjoint(with: ConfigurationCoverage.excluded.keys),
            "coverage disjoint")
        expect(
            Set(ConfigurationCoverage.included).union(ConfigurationCoverage.excluded.keys)
                == Set(AppSettingsKey.allCases),
            "all settings reviewed")
        for category in ["clipboard", "notes", "snippets", "learning", "manifest", "syncCategories"] {
            rejects("{\"schemaVersion\":1,\"\(category)\":{}}")
        }
        rejects(#"{"schemaVersion":1,"commands":{},"bindings":{}}"#)
        for json in [
            #"{"schemaVersion":1,"settings":{"windowCycleOnRepeat":true}}"#,
            #"{"schemaVersion":1,"settings":{"windowCycle":"future"}}"#,
            #"{"schemaVersion":1,"settings":{"paletteTransparency":101}}"#,
            #"{"schemaVersion":2}"#, #"{"schemaVersion":0}"#, #"{}"#,
            #"{"schemaVersion":1,"settings":{"appearance":"future"}}"#,
            #"{"schemaVersion":1,"settings":{"escapeKeyBehavior":"future"}}"#,
            #"{"schemaVersion":1,"settings":{"windowGap":-1}}"#,
            #"{"schemaVersion":1,"settings":{"compactMode":1}}"#,
            #"{"schemaVersion":1,"settings":{"snippetsEnabled":true}}"#,
            #"{"schemaVersion":1,"settings":{"clipboardTextSearchEnabled":true}}"#,
            #"{"schemaVersion":1,"credentials":{"token":"secret"}}"#,
            #"{"schemaVersion":1,"schemaVersion":1}"#,
            #"{"schemaVersion":1,"settings":{"appearance":"dark","\u0061ppearance":"light"}}"#,
            #"{"schemaVersion":1,"hotkeys":{"togglePalette":{"doubleTap":"future"}}}"#,
            #"{"schemaVersion":1,"hotkeys":{"togglePalette":{"keyCode":1}}}"#,
            #"{"schemaVersion":1,"hotkeys":{"togglePalette":{"keyCode":1,"modifiers":1}}}"#,
            #"{"schemaVersion":1,"hotkeys":{"extension:x":{"doubleTap":"shift"}}}"#,
            #"{"schemaVersion":1,"hotkeys":{"quicklink:gone":{"doubleTap":"shift"}}}"#,
            #"{"schemaVersion":1,"hotkeys":{"togglePalette":{"doubleTap":"shift"},"app:com.test.App":{"doubleTap":"shift"}}}"#,
            #"{"schemaVersion":1,"favoriteApps":["/Users/example/App.app"]}"#,
            #"{"schemaVersion":1,"hiddenLauncherKinds":{"extensionCommand":true}}"#,
            #"{"schemaVersion":1,"customCommands":{"invalid":{"name":"A","command":"true"}},"customCommandOrder":["invalid"]}"#,
            "<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> other", "{\"schemaVersion\":1", "[]", "null"
        ] { rejects(json) }
        do {
            _ = try PortableConfiguration(
                data: Data(repeating: 32, count: PortableConfiguration.maximumBytes + 1))
            fatalError("oversize accepted")
        } catch {}
        let dark = try changing(empty, section: "settings", key: "appearance", value: .string("dark"))
        let compact = try changing(empty, section: "settings", key: "compactMode", value: .bool(true))
        let disjoint = ConfigurationReconciliation.merge(
            base: empty.value, local: dark.value, incoming: compact.value)
        expect(disjoint.conflicts.isEmpty, "disjoint fields merge")
        let merged = try PortableConfiguration(value: disjoint.value)
        expect(
            merged["settings"]["appearance"] == .string("dark") && merged["settings"]["compactMode"].bool,
            "both edits retained")
        let light = try changing(empty, section: "settings", key: "appearance", value: .string("light"))
        expect(
            ConfigurationReconciliation.merge(base: empty.value, local: dark.value, incoming: light.value)
                .conflicts
                == ["settings/appearance"], "same field conflict")
        expect(
            ConfigurationReconciliation.merge(base: empty.value, local: dark.value, incoming: dark.value)
                .conflicts.isEmpty,
            "identical edits merge")
        let id = "00000000-0000-0000-0000-000000000001"
        let command = try parse(
            """
            {"schemaVersion":1,"customCommands":{"\(id)":{"name":"Example","command":"echo hello"}},
            "customCommandOrder":["\(id)"]}
            """)
        let secondID = "00000000-0000-0000-0000-000000000002"
        rejects(
            """
            {"schemaVersion":1,"customCommands":{"\(id)":{"name":"Example","command":"true"},
            "\(secondID)":{"name":" EXAMPLE ","command":"true"}},"customCommandOrder":["\(id)","\(secondID)"]}
            """)
        let approved = ConfigurationReconciliation.executableRevisions(command)
        expect(
            ConfigurationReconciliation.needsReview(command, approved: [:]) == [id],
            "incoming command needs approval")
        expect(
            ConfigurationReconciliation.needsReview(command, approved: approved).isEmpty,
            "approval survives reload")
        var commandValue = command["customCommands"][id].object
        commandValue["command"] = .string("echo changed")
        let changed = try changing(command, section: "customCommands", key: id, value: .object(commandValue))
        expect(
            ConfigurationReconciliation.needsReview(changed, approved: approved) == [id],
            "modified command invalidates approval")
        let bound = try changing(
            command, section: "hotkeys", key: "custom-command:" + id,
            value: .object(["doubleTap": .string("control")]))
        expect(
            ConfigurationReconciliation.needsReview(bound, approved: approved) == [id],
            "binding invalidates approval")
        expect(
            ConfigurationReconciliation.merge(
                base: command.value, local: empty.value, incoming: changed.value
            ).conflicts
                .contains("customCommands/" + id), "delete versus edit conflicts")
        let unsupported = try changing(
            empty, section: "hotkeys", key: "command:future-action",
            value: .object(["doubleTap": .string("control")]))
        let overlaid = ConfigurationReconciliation.applyingEdits(
            from: empty.value, to: dark.value, onto: unsupported.value)
        expect(
            overlaid["hotkeys"] == unsupported["hotkeys"], "unavailable target retained during local edits")
        let home = URL(fileURLWithPath: "/Users/example")
        expect(
            ConfigurationRepository.preset(home: home, environment: [:], bundleID: "com.tinycast.app").path
                == "/Users/example/.config/tinycast", "stable preset")
        expect(
            ConfigurationRepository.preset(
                home: home, environment: ["XDG_CONFIG_HOME": "relative"],
                bundleID: "com.tinycast.app.dev"
            ).path == "/Users/example/.config/tinycast-dev", "relative XDG ignored")
        expect(
            ConfigurationRepository.preset(
                home: home, environment: ["XDG_CONFIG_HOME": "/config"],
                bundleID: "com.tinycast.app.beta"
            ).path == "/config/tinycast-beta", "absolute XDG and beta")
        print("configuration schema, coverage, review, defaults, reconciliation and location tests passed")
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !condition() { fatalError(message) }
    }

    static func parse(_ json: String) throws -> PortableConfiguration {
        try PortableConfiguration(data: Data(json.utf8))
    }
    static func rejects(_ json: String) {
        do { _ = try parse(json); fatalError("accepted invalid JSON: " + json) } catch {}
    }

    static func changing(
        _ document: PortableConfiguration, section: String, key: String,
        value: ConfigurationValue
    ) throws -> PortableConfiguration {
        var root = document.value.object
        var fields = root[section]?.object ?? [:]
        fields[key] = value
        root[section] = .object(fields)
        return try PortableConfiguration(value: .object(root))
    }
}
