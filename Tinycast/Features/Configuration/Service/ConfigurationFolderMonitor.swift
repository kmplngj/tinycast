import Foundation

@MainActor
final class ConfigurationFolderMonitor {
    private var sources: [DispatchSourceFileSystemObject] = []

    func stop() {
        sources.forEach { $0.cancel() }
        sources = []
    }

    func watch(_ folder: URL, changed: @escaping @Sendable @MainActor () -> Void) async {
        let descriptors = await Task.detached(priority: .utility) {
            var paths: Set<String> = [folder.appendingPathComponent("settings.json").path]
            for root in [folder, folder.resolvingSymlinksInPath()] {
                var ancestor = root
                while ancestor.path != "/" {
                    paths.insert(ancestor.path)
                    ancestor.deleteLastPathComponent()
                }
            }
            return paths.compactMap { path -> Int32? in
                let descriptor = open(path, O_EVTONLY)
                return descriptor >= 0 ? descriptor : nil
            }
        }.value
        stop()
        for descriptor in descriptors {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
                queue: .main)
            source.setEventHandler { Task { @MainActor in changed() } }
            source.setCancelHandler { close(descriptor) }
            sources.append(source)
            source.resume()
        }
    }

    isolated deinit { stop() }
}
