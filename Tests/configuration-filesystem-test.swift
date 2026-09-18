import Foundation

@main
struct ConfigurationFilesystemTest {
    @MainActor
    final class Events { var count = 0 }

    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tinycast-configuration-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("settings.json")
        let base = try PortableConfiguration(data: Data(#"{"schemaVersion":1}"#.utf8))
        let bytes = try ConfigurationRepository.write(base, folder: folder, expected: nil)
        expect(
            try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["settings.json"],
            "activation writes only the portable document, with no data directories or manifest")
        let modification = try file.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        let unchanged = try ConfigurationRepository.write(base, folder: folder, expected: bytes)
        expect(unchanged == bytes, "no-op preserves bytes")
        expect(
            try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                == modification,
            "no-op preserves mtime")
        rejects { _ = try ConfigurationRepository.write(base, folder: folder, expected: nil) }

        let macA = ConfigurationRepository(directory: root.appendingPathComponent("mac-a"))
        let macB = ConfigurationRepository(directory: root.appendingPathComponent("mac-b"))
        var stateA = ConfigurationJournal(folder: folder, base: base, local: base)
        var stateB = stateA
        try macA.save(stateA)
        try macB.save(stateB)
        stateA.local = try changing(base, "appearance", .string("dark"))
        stateB.local = try changing(base, "compactMode", .bool(true))
        try macA.save(stateA)
        try macB.save(stateB)
        _ = try ConfigurationRepository.write(stateA.local!, folder: folder, expected: bytes)
        rejects { _ = try ConfigurationRepository.write(stateB.local!, folder: folder, expected: bytes) }
        let incoming = try ConfigurationRepository.read(folder: folder)
        let merged = ConfigurationReconciliation.merge(
            base: stateB.base!.value, local: stateB.local!.value,
            incoming: try PortableConfiguration(data: incoming).value)
        expect(merged.conflicts.isEmpty, "two independent states merge disjoint edits")
        stateB.local = try PortableConfiguration(value: merged.value)
        _ = try ConfigurationRepository.write(stateB.local!, folder: folder, expected: incoming)
        let reloaded = try PortableConfiguration(data: ConfigurationRepository.read(folder: folder))
        expect(
            reloaded["settings"]["appearance"] == .string("dark") && reloaded["settings"]["compactMode"].bool,
            "both Macs' changes persist")
        let retained = try macA.load()
        expect(retained.local == stateA.local && retained.base == base, "pending state survives restart")

        let events = Events()
        let monitor = ConfigurationFolderMonitor()
        await monitor.watch(folder) { events.count += 1 }
        let temporary = folder.appendingPathComponent("editor.tmp")
        try bytes.write(to: temporary)
        guard rename(temporary.path, file.path) == 0 else { fatalError("fixture rename") }
        try await Task.sleep(for: .milliseconds(500))
        expect(events.count > 0, "editor atomic replacement observed")
        await monitor.watch(folder) { events.count += 1 }
        var previous = events.count
        try Data("{\"schemaVersion\":".utf8).write(to: file)
        try await Task.sleep(for: .milliseconds(500))
        expect(events.count > previous, "partial in-place write observed")
        let partial = try ConfigurationRepository.read(folder: folder)
        rejects { _ = try PortableConfiguration(data: partial) }
        stateA.incoming = partial
        try macA.save(stateA)
        expect(try macA.load().local == retained.local, "invalid input retains last valid local state")
        try bytes.write(to: file, options: .atomic)
        await monitor.watch(folder) { events.count += 1 }
        previous = events.count
        let removedFolder = root.appendingPathComponent("disconnected")
        try FileManager.default.moveItem(at: folder, to: removedFolder)
        try await Task.sleep(for: .milliseconds(500))
        expect(events.count > previous, "directory replacement observed")
        rejects { _ = try ConfigurationRepository.read(folder: folder) }
        rejects { _ = try ConfigurationRepository.write(base, folder: folder, expected: bytes) }
        expect(!FileManager.default.fileExists(atPath: folder.path), "missing folder not recreated")
        await monitor.watch(folder) { events.count += 1 }
        previous = events.count
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try bytes.write(to: file)
        try await Task.sleep(for: .milliseconds(500))
        expect(events.count > previous, "reconnection observed through ancestor")
        expect(try ConfigurationRepository.read(folder: folder) == bytes, "reconnected file read")

        let symlink = root.appendingPathComponent("selected-link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: folder)
        expect(try ConfigurationRepository.read(folder: symlink) == bytes, "symlinked directory supported")
        await monitor.watch(symlink) { events.count += 1 }
        previous = events.count
        try FileManager.default.removeItem(at: symlink)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: removedFolder)
        try await Task.sleep(for: .milliseconds(500))
        expect(events.count > previous, "symlink target replacement observed")
        expect(try ConfigurationRepository.read(folder: symlink) == bytes, "new symlink target read")
        try FileManager.default.removeItem(at: file)
        rejects { _ = try ConfigurationRepository.write(base, folder: folder, expected: bytes) }
        expect(
            !FileManager.default.fileExists(atPath: file.path),
            "missing file never recreated by an active write")
        try FileManager.default.createSymbolicLink(
            at: file, withDestinationURL: removedFolder.appendingPathComponent("settings.json"))
        rejects { _ = try ConfigurationRepository.read(folder: folder) }
        rejects { _ = try ConfigurationRepository.write(base, folder: folder, expected: bytes) }
        try FileManager.default.removeItem(at: file)
        try bytes.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: file.path)
        rejects { _ = try ConfigurationRepository.inspect(folder: folder) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        rejects { _ = try ConfigurationRepository.write(reloaded, folder: folder, expected: bytes) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        for index in 0..<25 { try macA.recover(Data("{\"revision\":\(index)}".utf8)) }
        try macA.recover(Data("{\"revision\":24}".utf8))
        let recovery = try FileManager.default.contentsOfDirectory(
            at: macA.directory.appendingPathComponent("recovery"),
            includingPropertiesForKeys: nil)
        expect(recovery.count == 20, "bounded distinct recovery history")
        monitor.stop()
        print(
            "configuration filesystem, two-state reconciliation, observation, journal and recovery tests passed"
        )
    }

    static func expect(_ condition: Bool, _ message: String) { if !condition { fatalError(message) } }
    static func rejects(_ action: () throws -> Void) {
        do { try action(); fatalError("operation should have failed") } catch {}
    }
    static func changing(
        _ document: PortableConfiguration, _ key: String, _ value: ConfigurationValue
    ) throws -> PortableConfiguration {
        var root = document.value.object
        var settings = document["settings"].object
        settings[key] = value
        root["settings"] = .object(settings)
        return try PortableConfiguration(value: .object(root))
    }
}
