import AppKit
import SwiftUI
@testable import Tinycast_Dev

@main
@MainActor
enum ConfigurationRuntimeTest {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let identifier = Bundle.main.bundleIdentifier ?? ""
        precondition(identifier.hasPrefix("com.tinycast.configuration-test."))
        precondition(UserDefaults.standard.object(forKey: "fixtureInitialized") == nil)
        UserDefaults.standard.set(true, forKey: "fixtureInitialized")
        for key in AppSettingsKey.allCases where key.rawValue.hasSuffix("Enabled") {
            UserDefaults.standard.set(false, forKey: key.rawValue)
        }
        UserDefaults.standard.set(false, forKey: AppSettingsKey.supportReminders.rawValue)
        UserDefaults.standard.set("none", forKey: AppSettingsKey.hyperKey.rawValue)
        Task { @MainActor in
            do {
                try await run()
                print("PASS: built runtime, projection, review, conflicts, offline journal, backup and exit")
                fflush(stdout)
                if CommandLine.arguments.contains("--preview")
                    || Bundle.main.object(forInfoDictionaryKey: "FixturePreview") as? Bool == true
                {
                    AppCore.shared.settingsCoordinator.showSettings(tab: .backup)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    app.terminate(nil)
                }
            } catch {
                print("FAIL: \(error)")
                fflush(stdout)
                exit(1)
            }
        }
        app.run()
    }

    static func run() async throws {
        let core = AppCore.shared
        core.quicklinks.load()
        core.hotKeys.loadBindings()
        let privateFiles = [
            core.notesStore.notesDirectory.appendingPathComponent("local-fixture.md"),
            core.snippetsStore.snippetsDirectory.appendingPathComponent("local-fixture.md"),
            core.clipboardStore.imagesDir.appendingPathComponent("local-fixture.bin")
        ]
        let privateBytes = Data("Synthetic local data: never share this fixture".utf8)
        for file in privateFiles {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try privateBytes.write(to: file)
        }
        core.launcherRanking.record(itemKey: "com.example.Local", query: "local-only")
        await core.launcherRanking.flush()
        let localLearning = core.launcherRanking.records
        let coordinator = core.configurationCoordinator
        await coordinator.bootstrap()
        coordinator.startObserving()
        precondition(coordinator.folder == nil)
        let folder = AppPaths.applicationSupport().appendingPathComponent("shared-fixture")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("settings.json")
        await coordinator.prepare(folder)
        precondition(coordinator.selection?.document == nil)
        await coordinator.activate(replace: false)
        try await wait { coordinator.status == .current && !coordinator.busy }
        try check(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["settings.json"])
        try assertBackupMapping(core)
        core.settings.escapeKeyBehavior = .closeAndPopToRoot
        core.settings.compactMode = true
        try await wait {
            (try? read(file)["settings"]["compactMode"].bool) == true && coordinator.status == .current
        }
        var document = try read(file)
        document = try changing(document, section: "settings", key: "appearance", value: .string("light"))
        try document.encoded().write(to: file, options: .atomic)
        try await wait { core.settings.appearance == .light && coordinator.status == .current }

        try await entityRoundTrip(core, file: file)
        document = try read(file)

        let id = "00000000-0000-0000-0000-000000000001"
        var root = document.value.object
        root["customCommands"] = .object([
            id: .object(["name": .string("Reviewed command"), "command": .string("echo never-run")])
        ])
        root["customCommandOrder"] = .array([.string(id)])
        document = try PortableConfiguration(value: .object(root))
        try document.encoded().write(to: file, options: .atomic)
        try await wait { coordinator.status == .review && !coordinator.busy }
        precondition(core.customCommands.commands.isEmpty && !core.settings.customCommandsEnabled)
        await coordinator.approve()
        try await wait { core.customCommands.commands.count == 1 && coordinator.status == .current }
        try assertBackupMapping(core)
        let accepted = try Data(contentsOf: file)
        try Data("<<<<<<< HEAD\ninvalid".utf8).write(to: file)
        try await wait { coordinator.status == .invalid && !coordinator.busy }
        core.settings.windowGap = 2
        try await Task.sleep(for: .milliseconds(600))
        let invalidBytes = try Data(contentsOf: file)
        precondition(invalidBytes == Data("<<<<<<< HEAD\ninvalid".utf8))
        document = try changing(
            PortableConfiguration(data: accepted), section: "settings", key: "windowGap", value: .number(4))
        try document.encoded().write(to: file, options: .atomic)
        try await wait { coordinator.status == .conflict && !coordinator.busy }
        await coordinator.resolve(useFolder: false)
        try await wait {
            (try? read(file)["settings"]["windowGap"]) == .number(2) && coordinator.status == .current
        }

        var backup = SettingsBackup()
        backup.settings = SettingsBackup.SettingsData(compactMode: false)
        _ = coordinator.performLocalEdit { backup.apply(to: core) }
        try await wait {
            (try? read(file)["settings"]["compactMode"].bool) == false && coordinator.status == .current
        }
        document = try read(file)
        root = document.value.object
        root["customCommands"] = .object([:])
        root["customCommandOrder"] = .array([])
        root["hotkeys"] = .object(["command:future-action": .object(["doubleTap": .string("control")])])
        document = try PortableConfiguration(value: .object(root))
        try document.encoded().write(to: file, options: .atomic)
        try await wait { core.customCommands.commands.isEmpty && coordinator.status == .current }
        core.settings.compactMode = true
        try await wait {
            (try? read(file)["settings"]["compactMode"].bool) == true && coordinator.status == .current
        }
        let retainedBindings = try read(file)["hotkeys"].object
        precondition(retainedBindings["command:future-action"] != nil)
        let preserved = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        try await wait { coordinator.status == .unavailable && !coordinator.busy }
        core.settings.windowGap = 6
        try await Task.sleep(for: .milliseconds(600))
        precondition(!FileManager.default.fileExists(atPath: file.path))
        try preserved.write(to: file)
        try await wait {
            (try? read(file)["settings"]["windowGap"]) == .number(6) && coordinator.status == .current
        }
        let final = try Data(contentsOf: file)
        await coordinator.useThisMac()
        precondition(coordinator.folder == nil && core.settings.windowGap == 6)
        core.settings.windowGap = 8
        try await Task.sleep(for: .milliseconds(600))
        let afterExit = try Data(contentsOf: file)
        precondition(afterExit == final)
        await coordinator.prepare(folder)
        precondition(coordinator.selection?.document != nil)
        await coordinator.activate(replace: false)
        try await wait { coordinator.status == .current && !coordinator.busy }
        precondition(core.settings.windowGap == 6)
        for file in privateFiles { try check(try Data(contentsOf: file) == privateBytes) }
        precondition(core.launcherRanking.records == localLearning)
        try check(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["settings.json"])
        let extras = [
            "notes/incoming.md": "Incoming note must not be imported",
            "snippets/incoming.md": "Incoming snippet must not be imported",
            "clipboard/items.jsonl": "{}\n",
            "clipboard/images/incoming.bin": "Incoming image",
            "learning/ranking.json": "[]",
            "manifest.json": "{\"format\":1,\"counts\":{\"notes\":1}}"
        ]
        for (relative, contents) in extras {
            let target = folder.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: target)
        }
        core.settings.compactMode.toggle()
        await coordinator.flush()
        precondition(coordinator.status == .current)
        for file in privateFiles { try check(try Data(contentsOf: file) == privateBytes) }
        precondition(core.launcherRanking.records == localLearning)
        precondition(
            !FileManager.default.fileExists(
                atPath: core.notesStore.notesDirectory.appendingPathComponent("incoming.md").path))
        for (relative, contents) in extras {
            try check(try Data(contentsOf: folder.appendingPathComponent(relative)) == Data(contents.utf8))
        }
        print("Fixture data: \(folder.path)")
    }

    static func assertBackupMapping(_ core: AppCore) throws {
        let backup = try ConfigurationValue.encoding(SettingsBackup.gather(from: core))
        let portable = try ConfigurationRuntimeAdapter(core: core).gather()
        let syncOnly: Set<String> = ["schemaVersion", "customCommandOrder", "pinnedQuicklinks"]
        precondition(Set(portable.value.object.keys).subtracting(syncOnly) == Set(backup.object.keys))
        for (key, value) in portable["settings"].object {
            precondition(backup["settings"][key] == value, "Backup/sync setting drift: " + key)
        }
        for section in ["customCommands", "quicklinks"] {
            for var record in backup[section].array.map(\.object) {
                let id = record.removeValue(forKey: "id")!.string.lowercased()
                record.removeValue(forKey: "createdAt")
                record.removeValue(forKey: "pinnedAt")
                for (key, value) in record {
                    precondition(portable[section][id][key] == value, "Backup/sync record drift: " + key)
                }
            }
        }
    }

    static func entityRoundTrip(_ core: AppCore, file: URL) async throws {
        let quick = "00000000-0000-0000-0000-000000000002"
        let layout = "00000000-0000-0000-0000-000000000003"
        let entry = "00000000-0000-0000-0000-000000000004"
        let coordinator = core.configurationCoordinator
        var root = try read(file).value.object
        root["quicklinks"] = .object([
            quick: .object([
                "name": .string("Portable link"), "link": .string("https://example.com/{argument}")
            ])
        ])
        root["pinnedQuicklinks"] = .array([.string(quick)])
        root["windowLayouts"] = .object([
            layout: .object([
                "name": .string("Portable layout"),
                "entries": .object([
                    entry: .object([
                        "bundleID": .string("com.example.Uninstalled"), "displayRole": .string("secondary")
                    ])
                ]), "entryOrder": .array([.string(entry)])
            ])
        ])
        root["hotkeys"] = .object(["quicklink:" + quick: .object(["doubleTap": .string("option")])])
        root["favoriteApps"] = .array([.string("quicklink:" + quick)])
        root["launcherAliases"] = .object(["window-layout:" + layout: .string("desk")])
        root["hiddenLauncherItems"] = .object(["com.example.Uninstalled": .bool(true)])
        try PortableConfiguration(value: .object(root)).encoded().write(to: file, options: .atomic)
        try await wait {
            core.quicklinks.quicklinks.count == 1 && core.windowLayouts.layouts.count == 1
                && coordinator.status == .current
        }
        precondition(core.windowLayouts.layouts[0].entries[0].display.uuid == "role:secondary")
        precondition(core.hotKeys.allBindings[.quicklink(id: UUID(uuidString: quick)!)] != nil)
        precondition(core.favorites.keys.contains("quicklink:" + quick))
        precondition(core.aliases.aliases["window-layout:" + layout] == "desk")
        try assertBackupMapping(core)
        core.settings.windowGap = 1
        try await wait { (try? read(file)["settings"]["windowGap"]) == .number(1) }
        let persisted = try read(file)
        precondition(
            persisted["windowLayouts"][layout]["entries"][entry]["displayRole"] == .string("secondary"))
        precondition(persisted["hiddenLauncherItems"]["com.example.Uninstalled"] == .bool(true))
        root = persisted.value.object
        for section in ["quicklinks", "windowLayouts", "hotkeys", "launcherAliases", "hiddenLauncherItems"] {
            root[section] = .object([:])
        }
        root["favoriteApps"] = .array([])
        root["pinnedQuicklinks"] = .array([])
        try PortableConfiguration(value: .object(root)).encoded().write(to: file, options: .atomic)
        try await wait {
            core.quicklinks.quicklinks.isEmpty && core.windowLayouts.layouts.isEmpty
                && coordinator.status == .current
        }
        precondition(core.hotKeys.allBindings[.quicklink(id: UUID(uuidString: quick)!)] == nil)
        precondition(core.favorites.keys.isEmpty && core.aliases.aliases.isEmpty)
    }

    static func check(_ condition: @autoclosure () throws -> Bool) rethrows {
        let result = try condition()
        precondition(result)
    }

    static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<40 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw ConfigurationError.invalid(
            "Runtime did not settle within two seconds: " + AppCore.shared.configurationCoordinator.message)
    }

    static func read(_ url: URL) throws -> PortableConfiguration {
        try PortableConfiguration(data: Data(contentsOf: url))
    }

    static func changing(
        _ document: PortableConfiguration, section: String, key: String,
        value: ConfigurationValue
    ) throws -> PortableConfiguration {
        var root = document.value.object
        var fields = document[section].object
        fields[key] = value
        root[section] = .object(fields)
        return try PortableConfiguration(value: .object(root))
    }
}
