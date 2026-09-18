import Foundation

enum ConfigurationJSON {
    static func validateStructure(_ data: Data) throws {
        if String(data: data, encoding: .utf8)?.split(separator: "\n").contains(where: {
            $0.hasPrefix("<<<<<<< ") || $0.hasPrefix(">>>>>>> ") || $0 == "======="
        }) == true {
            throw ConfigurationError.invalid("Resolve Git conflict markers in settings.json, then Reload.")
        }
        var scanner = Scanner(bytes: Array(data))
        try scanner.value(depth: 0)
        scanner.whitespace()
        guard scanner.position == scanner.bytes.count else {
            throw ConfigurationError.invalid("Trailing JSON content.")
        }
    }

    private struct Scanner {
        let bytes: [UInt8]
        var position = 0
        var current: UInt8 { position < bytes.count ? bytes[position] : 0 }

        mutating func whitespace() {
            while [9, 10, 13, 32].contains(current) { position += 1 }
        }

        mutating func value(depth: Int) throws {
            guard depth <= 32 else { throw ConfigurationError.invalid("JSON nesting exceeds 32 levels.") }
            whitespace()
            switch current {
            case 123:
                position += 1
                whitespace()
                if current == 125 { position += 1; return }
                var keys: Set<String> = []
                while true {
                    whitespace()
                    let key = try string()
                    guard keys.insert(key).inserted else {
                        throw ConfigurationError.invalid("Duplicate JSON key: \(key).")
                    }
                    whitespace()
                    try consume(58)
                    try value(depth: depth + 1)
                    whitespace()
                    if current == 125 { position += 1; return }
                    try consume(44)
                }
            case 91:
                position += 1
                whitespace()
                if current == 93 { position += 1; return }
                while true {
                    try value(depth: depth + 1)
                    whitespace()
                    if current == 93 { position += 1; return }
                    try consume(44)
                }
            case 34: _ = try string()
            default:
                let start = position
                while current != 0, ![9, 10, 13, 32, 44, 93, 125].contains(current) { position += 1 }
                guard position > start else { throw ConfigurationError.invalid("Incomplete JSON value.") }
            }
        }

        mutating func consume(_ byte: UInt8) throws {
            guard current == byte else {
                throw ConfigurationError.invalid("Malformed or partially written JSON.")
            }
            position += 1
        }

        mutating func string() throws -> String {
            let start = position
            try consume(34)
            while position < bytes.count {
                let byte = current
                position += 1
                if byte == 34 {
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<position]))
                }
                if byte == 92 { position += 1 }
            }
            throw ConfigurationError.invalid("Unterminated JSON string.")
        }
    }
}
