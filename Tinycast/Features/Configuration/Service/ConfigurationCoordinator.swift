import AppKit

@MainActor
@Observable
final class ConfigurationCoordinator {
    enum Status: String {
        case current = "Current"
        case saving = "Saving"
        case unavailable = "Unavailable"
        case invalid = "Invalid configuration"
        case conflict = "Conflict"
        case review = "Review required"
    }

    struct Selection {
        let folder: URL
        let bytes: Data?
        let document: PortableConfiguration?
        let isPreset: Bool
    }

    private(set) var status: Status = .current
    private(set) var message = "Settings are stored on this Mac."
    private(set) var folder: URL?
    private(set) var selection: Selection?
    private(set) var differences: [String] = []
    private(set) var reviewText = ""
    private(set) var busy = false {
        didSet {
            if !busy {
                let waiters = idleWaiters
                idleWaiters = []
                for waiter in waiters { waiter.resume() }
            }
        }
    }
    let preset: URL
    @ObservationIgnored private let repository: ConfigurationRepository
    @ObservationIgnored private let adapter: ConfigurationRuntimeAdapter
    @ObservationIgnored private let monitor = ConfigurationFolderMonitor()
    @ObservationIgnored private var journal = ConfigurationJournal()
    @ObservationIgnored private var projection: PortableConfiguration?
    @ObservationIgnored private var candidate: PortableConfiguration?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var observers: [NotificationToken] = []
    @ObservationIgnored private var needsPass = false
    @ObservationIgnored private var applying = false
    @ObservationIgnored private var observing = false
    @ObservationIgnored private var retrySeconds: UInt64 = 2
    @ObservationIgnored private var journalAvailable = true
    @ObservationIgnored private var conflictReview = false
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    init(core: AppCore) {
        adapter = ConfigurationRuntimeAdapter(core: core)
        repository = ConfigurationRepository(
            directory: AppPaths.applicationSupport().appendingPathComponent("configuration"))
        preset = ConfigurationRepository.preset(
            home: FileManager.default.homeDirectoryForCurrentUser,
            environment: ProcessInfo.processInfo.environment,
            bundleID: Bundle.main.bundleIdentifier ?? "com.tinycast.app")
    }

    func bootstrap() async {
        do {
            let repository = repository
            journal = try await Task.detached(priority: .utility) { try repository.load() }.value
            folder = journal.folder
            guard folder != nil else { return }
            await reconcile()
            if projection == nil, let cached = journal.local ?? journal.base { try project(cached) }
        } catch {
            journalAvailable = false
            fail(error)
            message =
                "Local configuration recovery could not be read. Reveal recovery files before choosing another folder. "
                + message
        }
    }

    func startObserving() {
        observing = true
        track()
        for (center, name) in [
            (NotificationCenter.default, NSApplication.didBecomeActiveNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didMountNotification)
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.folder != nil else { return }
                    self.adapter.refreshAvailability()
                    self.reload()
                }
            }
            observers.append(NotificationToken(token, center: center))
        }
        let center = NotificationCenter.default
        let token = center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main)
        { [weak self] _ in
            Task { @MainActor [weak self] in self?.captureEdit() }
        }
        observers.append(NotificationToken(token, center: center))
    }

    private func track() {
        guard observing else { return }
        withObservationTracking {
            do { _ = try adapter.gather() } catch { fail(error) }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observing else { return }
                self.captureEdit()
                self.track()
            }
        }
    }

    private func captureEdit() {
        guard !applying, folder != nil, let projection, let local = journal.local else { return }
        do {
            let current = try adapter.gather()
            guard current != projection else { return }
            let edited = ConfigurationReconciliation.applyingEdits(
                from: projection.value, to: current.value, onto: local.value)
            let document = try PortableConfiguration(value: edited)
            journal.local = document
            self.projection = current
            let previousRevisions = ConfigurationReconciliation.executableRevisions(local)
            for (id, revision) in ConfigurationReconciliation.executableRevisions(document)
            where previousRevisions[id] != revision {
                journal.approved[id] = revision
            }
            if status == .current { status = .saving }
            schedule()
        } catch { fail(error) }
    }

    func performLocalEdit<T>(_ edit: () -> T) -> T {
        applying = true
        let result = edit()
        applying = false
        captureEdit()
        return result
    }

    func reload() {
        guard folder != nil else { return }
        captureEdit()
        schedule()
    }

    private func schedule() {
        needsPass = true
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.launchWorker()
        }
    }

    private func launchWorker() {
        guard worker == nil, !busy, needsPass else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            self.busy = true
            while self.needsPass, self.folder != nil {
                self.needsPass = false
                await self.reconcile()
            }
            self.busy = false
            self.worker = nil
        }
    }

    private func reconcile() async {
        guard let folder, let base = journal.base, let local = journal.local else { return }
        conflictReview = false
        do {
            try await persistJournal()
            await monitor.watch(folder) { [weak self] in self?.reload() }
            let bytes = try await Task.detached(priority: .utility) {
                try ConfigurationRepository.read(folder: folder)
            }.value
            journal.incoming = bytes
            let incoming: PortableConfiguration
            do {
                incoming = try await Task.detached(priority: .utility) {
                    try PortableConfiguration(data: bytes)
                }.value
            } catch {
                try await persistJournal()
                throw error
            }
            let currentLocal = journal.local ?? local
            let result = ConfigurationReconciliation.merge(
                base: base.value, local: currentLocal.value, incoming: incoming.value)
            guard result.conflicts.isEmpty else {
                candidate = incoming
                differences = result.conflicts
                status = .conflict
                message =
                    "Shared writes are paused. Edits remain in local recovery. Choose a version or resolve the file and Reload."
                try await persistJournal()
                return
            }
            let merged = try PortableConfiguration(value: result.value)
            let review = ConfigurationReconciliation.needsReview(merged, approved: journal.approved)
            guard review.isEmpty else {
                candidate = merged
                status = .review
                differences = ConfigurationReconciliation.diff(base.value, merged.value)
                reviewText = try executableDiff(base, merged, ids: review)
                message =
                    "Review changed shell commands and bindings before applying. Shared writes are paused."
                try await persistJournal()
                return
            }
            candidate = nil
            let repository = repository
            try await Task.detached(priority: .utility) {
                try repository.recover(base.encoded())
                try repository.recover(currentLocal.encoded())
                try repository.recover(bytes)
            }.value
            if journal.local != currentLocal { needsPass = true; return }
            if projection == nil || journal.local != merged { try project(merged) }
            journal.base = incoming
            journal.local = merged
            journal.incoming = nil
            try await persistJournal()
            if journal.local != merged { needsPass = true; return }
            if merged != incoming {
                status = .saving
                let written = try await Task.detached(priority: .utility) {
                    try ConfigurationRepository.write(merged, folder: folder, expected: bytes)
                }.value
                journal.base = merged
                try await Task.detached(priority: .utility) { try repository.recover(written) }.value
                try await persistJournal()
            }
            status = journal.local == journal.base ? .current : .saving
            message =
                status == .current ? "Folder settings are current." : "Local edits are waiting to be saved."
            differences = []
            reviewText = ""
            retry?.cancel()
            retrySeconds = 2
        } catch ConfigurationError.changed {
            needsPass = true
        } catch {
            fail(error)
            if status == .unavailable { scheduleRetry() }
        }
    }

    private func project(_ document: PortableConfiguration) throws {
        applying = true
        defer { applying = false }
        if projection != document { try adapter.apply(document) }
        projection = try adapter.gather()
    }

    private func persistJournal() async throws {
        let repository = repository
        let snapshot = journal
        try await Task.detached(priority: .utility) {
            if let local = snapshot.local { try repository.recover(local.encoded()) }
            try repository.save(snapshot)
        }.value
    }

    private func scheduleRetry() {
        retry?.cancel()
        let seconds = retrySeconds
        retrySeconds = min(retrySeconds * 2, 30)
        retry = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.reload()
        }
    }

    private func fail(_ error: Error) {
        switch error {
        case ConfigurationError.invalid, ConfigurationError.incompatible, is DecodingError: status = .invalid
        default: status = .unavailable
        }
        message =
            error.localizedDescription
            + (folder == nil ? "" : " Last valid settings are retained; shared writes are paused.")
    }

    func prepare(_ url: URL, isPreset: Bool = false) async {
        guard !busy, journalAvailable else { return }
        busy = true
        defer { busy = false; launchWorker() }
        do {
            let bytes = try await Task.detached(priority: .utility) {
                if isPreset, !FileManager.default.fileExists(atPath: url.path) { return Optional<Data>.none }
                return try ConfigurationRepository.inspect(folder: url)
            }.value
            let document = try bytes.map { try PortableConfiguration(data: $0) }
            if folder?.standardizedFileURL == url.standardizedFileURL, bytes == nil {
                throw ConfigurationError.unavailable(
                    "The active settings.json is missing. Restore the file and Reload.")
            }
            let current = try adapter.gather()
            selection = Selection(folder: url, bytes: bytes, document: document, isPreset: isPreset)
            differences = document.map { ConfigurationReconciliation.diff(current.value, $0.value) } ?? []
            reviewText =
                try document.map {
                    try executableDiff(
                        current, $0,
                        ids: ConfigurationReconciliation.needsReview($0, approved: journal.approved))
                } ?? ""
        } catch { fail(error) }
    }

    func cancelSelection() { selection = nil; differences = []; reviewText = ""; reload() }

    func activate(replace: Bool) async {
        guard let selection, !busy else { return }
        busy = true
        defer { busy = false; launchWorker() }
        do {
            let document = try !replace ? selection.document ?? adapter.gather() : adapter.gather()
            try adapter.validateProjection(document)
            let repository = repository
            let previousJournal = journal
            let previousRuntime = try adapter.gather()
            try await Task.detached(priority: .utility) {
                try repository.recover(previousRuntime.encoded())
                if let bytes = selection.bytes { try repository.recover(bytes) }
                if selection.isPreset { try ConfigurationRepository.createPreset(selection.folder) }
            }.value
            let bytes: Data
            if replace || selection.bytes == nil {
                bytes = try await Task.detached(priority: .utility) {
                    try ConfigurationRepository.write(
                        document, folder: selection.folder, expected: selection.bytes)
                }.value
            } else {
                bytes = try await Task.detached(priority: .utility) {
                    try ConfigurationRepository.read(folder: selection.folder)
                }.value
                guard bytes == selection.bytes else { throw ConfigurationError.changed }
            }
            let next = ConfigurationJournal(
                folder: selection.folder, base: document, local: document,
                approved: journal.approved.merging(ConfigurationReconciliation.executableRevisions(document))
                { _, new in new })
            try await Task.detached(priority: .utility) { try repository.save(next) }.value
            do {
                guard try adapter.gather() == previousRuntime else { throw ConfigurationError.changed }
                try project(document)
            } catch {
                try await Task.detached(priority: .utility) { try repository.save(previousJournal) }.value
                throw error
            }
            journal = next
            folder = selection.folder
            self.selection = nil
            candidate = nil
            differences = []
            reviewText = ""
            status = .current
            message = "Folder settings are current."
            await monitor.watch(selection.folder) { [weak self] in self?.reload() }
            needsPass = true
        } catch { fail(error) }
    }

    func useThisMac() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let repository = repository
            let next = ConfigurationJournal(
                folder: nil, base: journal.base, local: journal.local,
                incoming: journal.incoming, approved: journal.approved)
            if let local = journal.local {
                try await Task.detached(priority: .utility) { try repository.recover(local.encoded()) }.value
            }
            try await Task.detached(priority: .utility) { try repository.save(next) }.value
            journal = next
            folder = nil
            selection = nil
            monitor.stop()
            debounce?.cancel()
            retry?.cancel()
            needsPass = false
            status = .current
            message = "Current settings are kept on this Mac. The folder is unchanged."
        } catch { fail(error) }
    }

    func resolve(useFolder: Bool) async {
        guard !busy, let incomingBytes = journal.incoming, let folder else { return }
        busy = true
        defer { busy = false; launchWorker() }
        do {
            let bytes = try await Task.detached(priority: .utility) {
                try ConfigurationRepository.read(folder: folder)
            }.value
            guard bytes == incomingBytes else { throw ConfigurationError.changed }
            let incoming = try PortableConfiguration(data: bytes)
            let chosen = useFolder ? incoming : journal.local
            guard let chosen else { return }
            let repository = repository
            let old = journal.local
            try await Task.detached(priority: .utility) {
                if let old { try repository.recover(old.encoded()) }
                try repository.recover(bytes)
            }.value
            guard journal.local == old else { throw ConfigurationError.changed }
            let unapproved = ConfigurationReconciliation.needsReview(chosen, approved: journal.approved)
            if !unapproved.isEmpty {
                conflictReview = true
                candidate = chosen
                status = .review
                reviewText = try executableDiff(journal.base ?? chosen, chosen, ids: unapproved)
                message = "Review executable changes before applying the folder version."
                return
            }
            try project(chosen)
            journal.base = incoming
            journal.local = chosen
            journal.incoming = nil
            try await persistJournal()
            needsPass = true
        } catch { fail(error) }
    }

    func approve() async {
        guard let candidate, status == .review, !busy else { return }
        journal.approved.merge(ConfigurationReconciliation.executableRevisions(candidate)) { _, new in new }
        if conflictReview {
            conflictReview = false
            await resolve(useFolder: true)
        } else {
            reload()
        }
    }

    func reveal() {
        if let folder { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path) }
    }
    func revealRecovery() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repository.directory.path)
    }

    func chooseCustomFolder() async {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await prepare(url)
    }

    func flush() async {
        while busy { await withCheckedContinuation { idleWaiters.append($0) } }
        captureEdit()
        debounce?.cancel()
        needsPass = folder != nil
        launchWorker()
        await worker?.value
    }

    func stop() {
        observing = false
        observers = []
        debounce?.cancel()
        retry?.cancel()
        worker?.cancel()
        monitor.stop()
    }

    private func executableDiff(
        _ base: PortableConfiguration, _ new: PortableConfiguration, ids: [String]
    ) throws -> String {
        let old = ConfigurationReconciliation.executableRevisions(base)
        let incoming = ConfigurationReconciliation.executableRevisions(new)
        return try ids.map { id in
            let before = String(bytes: try (old[id] ?? .null).encoded(), encoding: .utf8)!
            let after = String(bytes: try (incoming[id] ?? .null).encoded(), encoding: .utf8)!
            return "Command \(id)\nBefore:\n\(before)\nAfter:\n\(after)"
        }.joined(separator: "\n")
    }
}
