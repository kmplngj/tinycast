import Foundation

enum ConfigurationError: LocalizedError, Equatable {
    case invalid(String)
    case incompatible(Int)
    case unavailable(String)
    case changed

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .unavailable(let message): message
        case .incompatible(let version):
            "Schema version \(version) is unsupported. Use a Tinycast build supporting this schema."
        case .changed: "The folder changed before saving. Reload to reconcile the new version."
        }
    }
}
