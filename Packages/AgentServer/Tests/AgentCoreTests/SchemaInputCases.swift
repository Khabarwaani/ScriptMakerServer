import Foundation
@testable import AgentCore

/// Test-only schema discovery and fixture expansion. No agent IDs or field names.
/// Constraints that cannot be synthesized require declarative schema examples.
struct SchemaInputCases {
    struct Field {
        let tokens: [String]
        let schema: JSONValue
        let required: Bool
        var path: String { tokens.reduce("") { OutputValidator.pointer($0, $1) } }
    }
    let schema: JSONValue

    func baseline(_ example: JSONValue) throws -> JSONValue {
        try sample(schema, seed: example, depth: 0)
    }

    func fields(in input: JSONValue) throws -> [Field] {
        var result: [Field] = []
        try walk(input, node: schema, tokens: [], depth: 0, result: &result)
        return result.sorted { $0.path < $1.path }
    }

    func defaultValue(for field: Field, in input: JSONValue) throws -> JSONValue? {
        var node = schema
        var instance = input
        for index in field.tokens.indices {
            let active = try expanded(node, value: instance, depth: index)
            let remaining = Array(field.tokens.dropFirst(index))
            // Object defaults merge through objects, but never rewrite supplied array elements.
            var current = instance
            var crossesArray = false
            for token in remaining.dropLast() {
                if current.array != nil { crossesArray = true; break }
                current = current[token] ?? .null
            }
            if !crossesArray, let fallback = active["default"],
               let value = Self.value(fallback, at: remaining) { return value }
            let token = field.tokens[index]
            if let object = instance.object {
                node = active["properties"]?[token] ?? .bool(true)
                instance = object[token] ?? .null
            } else if let array = instance.array, let offset = Int(token), array.indices.contains(offset) {
                let prefixes = active["prefixItems"]?.array ?? []
                node = offset < prefixes.count ? prefixes[offset] : active["items"] ?? .bool(true)
                instance = array[offset]
            }
        }
        return field.schema["default"]
    }

    private func expanded(_ node: JSONValue, value: JSONValue?, depth: Int) throws -> JSONValue {
        guard depth < 64 else { throw gap("Recursive schema needs a finite example.") }
        var object = node.object ?? [:]
        var children = node["allOf"]?.array ?? []
        if let ref = node["$ref"]?.string, let resolved = OutputValidator.resolve(ref, root: schema) { children.append(resolved) }
        for keyword in ["anyOf", "oneOf"] {
            if let branches = node[keyword]?.array {
                guard let value, let branch = branches.first(where: { OutputValidator.matches(value, schema: $0, root: schema, depth: 0) }) else {
                    throw gap("Schema alternatives need a matching example.")
                }
                children.append(branch)
            }
        }
        if let condition = node["if"], let value {
            if let branch = OutputValidator.matches(value, schema: condition, root: schema, depth: 0) ? node["then"] : node["else"] { children.append(branch) }
        }
        for child in children {
            let expandedChild = try expanded(child, value: value, depth: depth + 1)
            for (key, childValue) in expandedChild.object ?? [:] {
                if key == "properties" {
                    var properties = object[key]?.object ?? [:]
                    for (name, definition) in childValue.object ?? [:] {
                        if let existing = properties[name], existing != definition {
                            properties[name] = .object(["allOf": .array([existing, definition])])
                        } else { properties[name] = definition }
                    }
                    object[key] = .object(properties)
                } else if key == "required" {
                    let required = Set((object[key]?.array ?? []).compactMap(\.string) + (childValue.array ?? []).compactMap(\.string))
                    object[key] = .array(required.sorted().map(JSONValue.string))
                } else if object[key] == nil { object[key] = childValue }
            }
        }
        return .object(object)
    }

    private func sample(_ original: JSONValue, seed: JSONValue?, depth: Int) throws -> JSONValue {
        guard depth < 64 else { throw gap("Fixture expansion exceeds depth 64.") }
        let initial = seed ?? original["examples"]?.array?.first ?? original["default"] ?? original["const"] ?? original["enum"]?.array?.first
        let node = try expanded(original, value: initial, depth: depth)
        let types = node["type"]?.string.map { [$0] } ?? node["type"]?.array?.compactMap(\.string) ?? []
        let objectType = initial?.object != nil || types.contains("object") || node["properties"] != nil
        if objectType {
            var object = initial?.object ?? [:]
            for (key, child) in node["properties"]?.object ?? [:] {
                do { object[key] = try sample(child, seed: object[key], depth: depth + 1) }
                catch { throw gap("Field '\(key)' needs a schema example: \(error)") }
            }
            let value = JSONValue.object(object)
            guard OutputValidator.matches(value, schema: original, root: schema, depth: 0) else {
                throw gap("Expanded object does not satisfy its schema; provide a complete example.")
            }
            return value
        }
        if initial?.array != nil || types.contains("array") {
            let prefixes = node["prefixItems"]?.array ?? []
            var values = initial?.array ?? []
            // Exercise nested item fields even if the example contains an empty optional array.
            let target = max(Int(node["minItems"]?.number ?? 0), min(1, Int(node["maxItems"]?.number ?? 1)))
            while values.count < target { values.append(.null) }
            for index in values.indices {
                let child = index < prefixes.count ? prefixes[index] : node["items"] ?? .bool(true)
                values[index] = try sample(child, seed: values[index] == .null ? nil : values[index], depth: depth + 1)
            }
            let value = JSONValue.array(values)
            guard OutputValidator.matches(value, schema: original, root: schema, depth: 0) else { throw gap("Array needs a valid schema example.") }
            return value
        }
        var candidates = [initial, node["default"], node["const"]].compactMap { $0 }
        candidates += node["examples"]?.array ?? []
        candidates += node["enum"]?.array ?? []
        let minimum = node["minimum"]?.number ?? 0
        let numeric = max(minimum, (node["exclusiveMinimum"]?.number ?? (minimum - 1)) + 1)
        let length = max(1, Int(node["minLength"]?.number ?? 1))
        candidates += [.number(numeric), .number(numeric.rounded(.up)), .bool(false), .null,
                       .string(String(repeating: "x", count: min(length, 4096))),
                       .string("https://example.test"), .string("01-01-26")]
        guard let value = candidates.first(where: { OutputValidator.matches($0, schema: original, root: schema, depth: 0) }) else {
            throw gap("Constraint cannot be synthesized; add a default, enum or schema example.")
        }
        return value
    }

    private func walk(_ value: JSONValue, node original: JSONValue, tokens: [String], depth: Int, result: inout [Field]) throws {
        let node = try expanded(original, value: value, depth: depth)
        if let object = value.object {
            let required = Set(node["required"]?.array?.compactMap(\.string) ?? [])
            for (key, child) in node["properties"]?.object ?? [:] {
                let path = tokens + [key]
                result.append(Field(tokens: path, schema: try expanded(child, value: object[key], depth: depth + 1), required: required.contains(key)))
                if let item = object[key] { try walk(item, node: child, tokens: path, depth: depth + 1, result: &result) }
            }
        }
        if let array = value.array {
            let prefixes = node["prefixItems"]?.array ?? []
            for (index, item) in array.enumerated() {
                let child = index < prefixes.count ? prefixes[index] : node["items"] ?? .bool(true)
                try walk(item, node: child, tokens: tokens + [String(index)], depth: depth + 1, result: &result)
            }
        }
    }

    static func value(_ input: JSONValue, at tokens: [String]) -> JSONValue? {
        guard let first = tokens.first else { return input }
        if let object = input.object, let next = object[first] { return value(next, at: Array(tokens.dropFirst())) }
        if let array = input.array, let index = Int(first), array.indices.contains(index) { return value(array[index], at: Array(tokens.dropFirst())) }
        return nil
    }

    static func removing(_ input: JSONValue, at tokens: [String]) -> JSONValue {
        guard let first = tokens.first else { return input }
        if var object = input.object {
            if tokens.count == 1 { object[first] = nil }
            else if let child = object[first] { object[first] = removing(child, at: Array(tokens.dropFirst())) }
            return .object(object)
        }
        if var array = input.array, let index = Int(first), array.indices.contains(index) {
            array[index] = removing(array[index], at: Array(tokens.dropFirst()))
            return .array(array)
        }
        return input
    }

    private func gap(_ message: String) -> AgentError { AgentError("schema_test_coverage_gap", message) }
}
