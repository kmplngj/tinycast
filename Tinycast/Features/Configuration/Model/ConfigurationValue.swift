import Foundation

indirect enum ConfigurationValue: Codable, Equatable, Sendable {
    case object([String: ConfigurationValue])
    case array([ConfigurationValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let decoded = try? value.decode(Bool.self) {
            self = .bool(decoded)
        } else if let decoded = try? value.decode(Double.self) {
            self = .number(decoded)
        } else if let decoded = try? value.decode(String.self) {
            self = .string(decoded)
        } else if let decoded = try? value.decode([String: Self].self) {
            self = .object(decoded)
        } else {
            self = .array(try value.decode([Self].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }

    var object: [String: Self] { if case .object(let value) = self { value } else { [:] } }
    var array: [Self] { if case .array(let value) = self { value } else { [] } }
    var string: String { if case .string(let value) = self { value } else { "" } }
    var number: Double { if case .number(let value) = self { value } else { 0 } }
    var bool: Bool { self == .bool(true) }
    subscript(_ key: String) -> Self { object[key] ?? .null }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data([10])
    }

    static func encoding(_ value: some Encodable) throws -> Self {
        try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(value))
    }

    func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: encoded())
    }
}
