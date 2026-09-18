import Foundation

struct ConfigurationJournal: Codable, Equatable, Sendable {
    var folder: URL?
    var base: PortableConfiguration?
    var local: PortableConfiguration?
    var incoming: Data?
    var approved: [String: ConfigurationValue] = [:]
}
