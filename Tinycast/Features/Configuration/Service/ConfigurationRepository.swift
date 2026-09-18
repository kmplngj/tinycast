import CryptoKit
import Foundation

struct ConfigurationRepository: Sendable {
    let directory: URL

    func load() throws -> ConfigurationJournal {
        let url = directory.appendingPathComponent("journal.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return ConfigurationJournal() }
        return try JSONDecoder().decode(ConfigurationJournal.self, from: Data(contentsOf: url))
    }

    func save(_ journal: ConfigurationJournal) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let url = directory.appendingPathComponent("journal.json")
        let data = try encoder.encode(journal)
        if FileManager.default.fileExists(atPath: url.path), try Data(contentsOf: url) == data { return }
        try data.write(to: url, options: .atomic)
    }

    func recover(_ data: Data) throws {
        let recovery = directory.appendingPathComponent("recovery", isDirectory: true)
        try FileManager.default.createDirectory(
            at: recovery, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let url = recovery.appendingPathComponent(hash + ".json")
        if FileManager.default.fileExists(atPath: url.path) { return }
        try data.write(to: url, options: .atomic)
        let files = try FileManager.default.contentsOfDirectory(
            at: recovery,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        .sorted {
            let left =
                try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                ?? .distantPast
            let right =
                try $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                ?? .distantPast
            return left > right
        }
        for file in files.dropFirst(20) { try FileManager.default.removeItem(at: file) }
    }

    static func read(folder: URL) throws -> Data {
        let url = try file(in: folder)
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(
            ConfigurationError.unavailable("The folder could not be read."))
        NSFileCoordinator().coordinate(
            readingItemAt: url, options: .withoutChanges, error: &coordinationError
        ) { target in
            result = Result { try readFile(target) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func inspect(folder: URL) throws -> Data? {
        let url = try file(in: folder)
        var info = stat()
        if lstat(url.path, &info) != 0 {
            guard errno == ENOENT else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            guard FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path) else {
                throw ConfigurationError.unavailable("The selected folder is not writable.")
            }
            return nil
        }
        guard FileManager.default.isWritableFile(atPath: url.path),
            FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
        else { throw ConfigurationError.unavailable("settings.json or its folder is not writable.") }
        return try read(folder: folder)
    }

    static func write(_ document: PortableConfiguration, folder: URL, expected: Data?) throws -> Data {
        let url = try file(in: folder)
        let bytes = try document.encoded()
        guard bytes.count <= PortableConfiguration.maximumBytes else {
            throw ConfigurationError.invalid("Portable settings exceed the 2 MiB file limit.")
        }
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(
            ConfigurationError.unavailable("The folder could not be written."))
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError)
        { target in
            result = Result {
                if let expected {
                    let current = try readFile(target)
                    guard current == expected else { throw ConfigurationError.changed }
                    if try PortableConfiguration(data: current) == document { return current }
                    guard FileManager.default.isWritableFile(atPath: target.path) else {
                        throw ConfigurationError.unavailable("settings.json is not writable.")
                    }
                } else {
                    var info = stat()
                    guard lstat(target.path, &info) != 0, errno == ENOENT else {
                        throw ConfigurationError.changed
                    }
                }
                let temporary = target.deletingLastPathComponent().appendingPathComponent(
                    ".tinycast-" + UUID().uuidString)
                try bytes.write(to: temporary, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: temporary) }
                if expected == nil {
                    guard link(temporary.path, target.path) == 0 else { throw ConfigurationError.changed }
                } else {
                    guard try readFile(target) == expected else { throw ConfigurationError.changed }
                    guard rename(temporary.path, target.path) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                }
                return bytes
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func createPreset(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static func preset(home: URL, environment: [String: String], bundleID: String) -> URL {
        let root: URL
        if let path = environment["XDG_CONFIG_HOME"], path.hasPrefix("/") {
            root = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            root = home.appendingPathComponent(".config", isDirectory: true)
        }
        let name =
            bundleID == "com.tinycast.app"
            ? "tinycast"
            : bundleID == "com.tinycast.app.dev"
                ? "tinycast-dev"
                : bundleID == "com.tinycast.app.beta" ? "tinycast-beta" : "tinycast-" + bundleID
        return root.appendingPathComponent(name, isDirectory: true)
    }

    private static func file(in folder: URL) throws -> URL {
        let resolved = folder.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            throw ConfigurationError.unavailable("The selected folder is unavailable. Restore it and Reload.")
        }
        let url = resolved.appendingPathComponent("settings.json")
        var info = stat()
        if lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFLNK {
            throw ConfigurationError.invalid(
                "settings.json is a symlink. Select its target's parent directory instead.")
        }
        return url
    }

    private static func readFile(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw ConfigurationError.unavailable(
                "settings.json is missing or unreadable. Restore it and Reload.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw ConfigurationError.invalid("settings.json must be a regular file.")
        }
        let bytes = try handle.read(upToCount: PortableConfiguration.maximumBytes + 1) ?? Data()
        guard bytes.count <= PortableConfiguration.maximumBytes else {
            throw ConfigurationError.invalid("settings.json exceeds 2 MiB.")
        }
        return bytes
    }
}
