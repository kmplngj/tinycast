import Foundation

indirect enum ConfigurationRule: Sendable {
    case text
    case flag
    case number(ClosedRange<Double>, integer: Bool)
    case choice([ConfigurationValue])
    case optional(ConfigurationRule)
    case list(ConfigurationRule)
    case map(ConfigurationRule)
    case fields([String: ConfigurationRule], defaults: [String: ConfigurationValue])

    func validate(_ value: ConfigurationValue, at path: String) throws -> ConfigurationValue {
        func invalid(_ reason: String) -> ConfigurationError { .invalid("\(path): \(reason)") }
        switch (self, value) {
        case (.text, .string(let text)):
            guard text.utf8.count <= 65_536, !text.contains("\0") else {
                throw invalid("text is too long or contains a null character.")
            }
        case (.flag, .bool): break
        case (.number(let range, let integer), .number(let number)):
            guard number.isFinite, range.contains(number), !integer || number.rounded() == number else {
                throw invalid("number is outside the supported range.")
            }
        case (.choice(let choices), _):
            guard choices.contains(value) else { throw invalid("unsupported value; file left unchanged.") }
        case (.optional, .null): break
        case (.optional(let rule), _): return try rule.validate(value, at: path)
        case (.list(let rule), .array(let values)):
            guard values.count <= 10_000 else { throw invalid("too many entries.") }
            return .array(
                try values.enumerated().map { try rule.validate($0.element, at: "\(path)[\($0.offset)]") })
        case (.map(let rule), .object(let values)):
            guard values.count <= 10_000 else { throw invalid("too many entries.") }
            var result: [String: ConfigurationValue] = [:]
            for (key, child) in values {
                guard !key.isEmpty, key.utf8.count <= 512, !key.contains("\0") else {
                    throw invalid("invalid entity key.")
                }
                result[key] = try rule.validate(child, at: path + "/" + key)
            }
            return .object(result)
        case (.fields(let fields, let defaults), .object(let values)):
            let unknown = Set(values.keys).subtracting(fields.keys)
            guard unknown.isEmpty else {
                throw invalid(
                    "unrecognized fields: \(unknown.sorted().joined(separator: ", ")). "
                        + "Remove them or use a compatible build. Write mode is refused.")
            }
            var result = defaults
            for (key, rule) in fields {
                guard let child = values[key] ?? defaults[key] else { throw invalid("missing \(key).") }
                result[key] = try rule.validate(child, at: path + "/" + key)
            }
            return .object(result)
        default: throw invalid("incorrect JSON type.")
        }
        return value
    }

    static func strings(_ values: [String]) -> Self { .choice(values.map(ConfigurationValue.string)) }
    static func integers(_ values: [Int]) -> Self { .choice(values.map { .number(Double($0)) }) }
}
