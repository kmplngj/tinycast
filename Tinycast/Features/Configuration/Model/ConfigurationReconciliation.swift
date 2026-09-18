import Foundation

enum ConfigurationReconciliation {
    struct Result: Sendable {
        let value: ConfigurationValue
        let conflicts: [String]
    }

    static func merge(
        base: ConfigurationValue, local: ConfigurationValue, incoming: ConfigurationValue
    ) -> Result {
        var conflicts: [String] = []
        func mergeValue(
            _ base: ConfigurationValue?, _ local: ConfigurationValue?,
            _ incoming: ConfigurationValue?, path: [String]
        ) -> ConfigurationValue? {
            if local == base { return incoming }
            if incoming == base || incoming == local { return local }
            if path.count < 2, case .object(let b) = base, case .object(let l) = local,
                case .object(let i) = incoming
            {
                var result: [String: ConfigurationValue] = [:]
                for key in Set(b.keys).union(l.keys).union(i.keys).sorted() {
                    result[key] = mergeValue(b[key], l[key], i[key], path: path + [key])
                }
                return .object(result)
            }
            conflicts.append(path.joined(separator: "/"))
            return local
        }
        let value = mergeValue(base, local, incoming, path: []) ?? local
        return Result(value: value, conflicts: conflicts)
    }

    static func applyingEdits(
        from base: ConfigurationValue, to edited: ConfigurationValue,
        onto authoritative: ConfigurationValue
    ) -> ConfigurationValue {
        if base == edited { return authoritative }
        guard case .object(let old) = base, case .object(let new) = edited,
            case .object(var result) = authoritative
        else { return edited }
        for section in Set(old.keys).union(new.keys) where old[section] != new[section] {
            if case .object(let oldEntries) = old[section], case .object(let newEntries) = new[section] {
                var entries = result[section]?.object ?? [:]
                for key in Set(oldEntries.keys).union(newEntries.keys)
                where oldEntries[key] != newEntries[key] {
                    entries[key] = newEntries[key]
                }
                result[section] = .object(entries)
            } else {
                result[section] = new[section]
            }
        }
        return .object(result)
    }

    static func diff(_ base: ConfigurationValue, _ incoming: ConfigurationValue) -> [String] {
        var lines: [String] = []
        for section in Set(base.object.keys).union(incoming.object.keys).sorted()
        where base[section] != incoming[section] {
            if case .object(let old) = base[section], case .object(let new) = incoming[section] {
                for key in Set(old.keys).union(new.keys).sorted() where old[key] != new[key] {
                    let action = old[key] == nil ? "Add" : new[key] == nil ? "Delete" : "Change"
                    lines.append(
                        "\(action) \(section)/\(key): \(summary(old[key])) → \(summary(new[key]))")
                }
            } else {
                lines.append("Change \(section): \(summary(base[section])) → \(summary(incoming[section]))")
            }
        }
        return lines
    }

    private static func summary(_ value: ConfigurationValue?) -> String {
        guard let value else { return "absent" }
        switch value {
        case .string(let text): return "\"" + String(text.prefix(100)) + "\""
        case .bool(let flag): return flag ? "true" : "false"
        case .number(let number): return String(number)
        case .null: return "null"
        case .array(let values): return "\(values.count) ordered entries"
        case .object(let fields):
            return fields["name"].map { summary($0) } ?? "\(fields.count) fields"
        }
    }

    static func executableRevisions(_ document: PortableConfiguration) -> [String: ConfigurationValue] {
        document["customCommands"].object.mapValues { $0 }.reduce(into: [:]) { result, entry in
            result[entry.key] = .object([
                "definition": entry.value,
                "binding": document["hotkeys"]["custom-command:" + entry.key]
            ])
        }
    }

    static func needsReview(
        _ document: PortableConfiguration, approved: [String: ConfigurationValue]
    ) -> [String] {
        executableRevisions(document).filter { approved[$0.key] != $0.value }.keys.sorted()
    }
}
