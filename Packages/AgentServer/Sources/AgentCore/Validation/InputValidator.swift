import Foundation

/// Provider-independent preparation. Defaults are annotations with explicit server semantics:
/// fill absent values only, then validate the complete effective input.
public enum InputValidator {
    public static func prepare(_ input: JSONValue, schema: JSONValue, agentID: String, version: String) throws -> JSONValue {
        let effective = try defaults(input, schema: schema, root: schema, depth: 0)
        let violations = OutputValidator.violations(effective, schema: schema)
        guard violations.isEmpty else {
            let missing = violations.filter { $0["keyword"] == .string("required") }.count
            let summary = missing == violations.count
                ? "Input validation failed: \(missing) required field(s) are missing."
                : "Input validation failed: \(violations.count) field constraint(s) failed."
            throw AgentError("input_schema_validation_failed", summary, details: .object([
                "agent_id": .string(agentID), "version": .string(version),
                "violations": .array(Array(violations.prefix(50))), "truncated": .bool(violations.count > 50),
            ]))
        }
        return effective
    }

    static func defaults(_ value: JSONValue, schema: JSONValue, root: JSONValue, depth: Int) throws -> JSONValue {
        guard depth < 64 else { throw invalid("Default expansion exceeds the schema recursion limit.") }
        guard let node = schema.object else { return value }
        var candidates: [JSONValue] = [value]
        if let reference = node["$ref"]?.string, let target = OutputValidator.resolve(reference, root: root) {
            candidates.append(try defaults(value, schema: target, root: root, depth: depth + 1))
        }
        for child in node["allOf"]?.array ?? [] {
            candidates.append(try defaults(value, schema: child, root: root, depth: depth + 1))
        }
        for keyword in ["anyOf", "oneOf"] {
            if let branches = node[keyword]?.array {
                var possible: [JSONValue] = []
                for branch in branches {
                    let prepared = try defaults(value, schema: branch, root: root, depth: depth + 1)
                    if OutputValidator.matches(prepared, schema: branch, root: root, depth: 0) { possible.append(prepared) }
                }
                if let first = possible.first {
                    guard possible.allSatisfy({ $0 == first }) else {
                        throw invalid("Schema alternatives provide ambiguous defaults.")
                    }
                    candidates.append(first)
                }
            }
        }
        if let condition = node["if"] {
            let branch = OutputValidator.matches(value, schema: condition, root: root, depth: 0) ? node["then"] : node["else"]
            if let branch { candidates.append(try defaults(value, schema: branch, root: root, depth: depth + 1)) }
        }
        var local = value
        if var object = value.object {
            // An object-level default also supplies defaults for missing members of a supplied object.
            if let fallback = node["default"] {
                object = fillMissing(.object(object), from: fallback).object ?? object
            }
            for (key, child) in node["properties"]?.object ?? [:] {
                if object[key] == nil { object[key] = try declaredDefault(child, root: root, depth: depth + 1) }
                if let present = object[key] {
                    object[key] = try defaults(present, schema: child, root: root, depth: depth + 1)
                }
            }
            if let additional = node["additionalProperties"], additional.object != nil {
                let properties = node["properties"]?.object ?? [:]
                for key in object.keys where properties[key] == nil {
                    object[key] = try defaults(object[key]!, schema: additional, root: root, depth: depth + 1)
                }
            }
            local = .object(object)
        } else if let values = value.array {
            let prefixes = node["prefixItems"]?.array ?? []
            local = .array(try values.enumerated().map { index, item in
                let child = index < prefixes.count ? prefixes[index] : node["items"] ?? .bool(true)
                return try defaults(item, schema: child, root: root, depth: depth + 1)
            })
        }
        candidates.append(local)
        return try candidates.reduce(value) { try merge($0, $1) }
    }

    private static func declaredDefault(_ schema: JSONValue, root: JSONValue, depth: Int) throws -> JSONValue? {
        guard depth < 64 else { throw invalid("Default reference exceeds the schema recursion limit.") }
        var values: [JSONValue] = []
        if let value = schema["default"] { values.append(value) }
        if let reference = schema["$ref"]?.string, let target = OutputValidator.resolve(reference, root: root),
           let value = try declaredDefault(target, root: root, depth: depth + 1) { values.append(value) }
        for child in schema["allOf"]?.array ?? [] {
            if let value = try declaredDefault(child, root: root, depth: depth + 1) { values.append(value) }
        }
        guard let first = values.first else { return nil }
        return try values.dropFirst().reduce(first) { try merge($0, $1) }
    }

    private static func fillMissing(_ value: JSONValue, from fallback: JSONValue) -> JSONValue {
        guard var object = value.object, let defaults = fallback.object else { return value }
        for (key, defaultValue) in defaults {
            object[key] = object[key].map { fillMissing($0, from: defaultValue) } ?? defaultValue
        }
        return .object(object)
    }

    private static func merge(_ lhs: JSONValue, _ rhs: JSONValue) throws -> JSONValue {
        if lhs == rhs { return lhs }
        if var object = lhs.object, let other = rhs.object {
            for (key, value) in other {
                object[key] = try object[key].map { try merge($0, value) } ?? value
            }
            return .object(object)
        }
        if let left = lhs.array, let right = rhs.array, left.count == right.count {
            return .array(try zip(left, right).map { try merge($0, $1) })
        }
        throw invalid("Schema supplies conflicting defaults for the same field.")
    }

    private static func invalid(_ message: String) -> AgentError { AgentError("invalid_agent_definition", message) }
}
