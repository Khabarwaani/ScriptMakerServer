import Foundation

/// Deliberately bounded JSON Schema support. Unsupported assertions make a
/// definition unavailable, rather than being silently ignored.
public enum OutputValidator {
    private static let annotations: Set<String> = [
        "$schema", "$id", "$comment", "title", "description", "default", "examples", "deprecated", "readOnly",
        "writeOnly",
    ]
    private static let assertions: Set<String> = [
        "$ref", "$defs", "definitions", "type", "properties", "required", "additionalProperties", "items",
        "prefixItems", "minItems", "maxItems", "uniqueItems", "minLength", "maxLength", "pattern", "minimum",
        "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf", "enum", "const", "allOf", "anyOf",
        "oneOf", "not", "minProperties", "maxProperties", "if", "then", "else",
    ]
    private static let types: Set<String> = [
        "object", "array", "string", "number", "integer", "boolean", "null",
    ]

    public static func checkSchema(_ schema: JSONValue) throws {
        try check(schema, root: schema, depth: 0)
    }
    private static func invalid() -> AgentError {
        AgentError("invalid_agent_definition", "The JSON schema is invalid or uses unsupported constraints.")
    }
    private static func check(_ schema: JSONValue, root: JSONValue, depth: Int) throws {
        guard depth < 64 else { throw invalid() }
        if schema.bool != nil { return }
        guard let object = schema.object, Set(object.keys).isSubset(of: annotations.union(assertions)) else {
            throw invalid()
        }
        if let dialect = object["$schema"]?.string,
            dialect != "https://json-schema.org/draft/2020-12/schema"
        {
            throw invalid()
        }
        if let type = object["type"] {
            let values = type.string.map { [$0] } ?? type.array?.compactMap(\.string)
            guard let values, !values.isEmpty, values.allSatisfy({ types.contains($0) }),
                Set(values).count == values.count,
                type.array == nil || values.count == type.array?.count
            else { throw invalid() }
        }
        for key in ["properties", "$defs", "definitions"] {
            if let value = object[key] {
                guard let children = value.object else { throw invalid() }
                for child in children.values { try check(child, root: root, depth: depth + 1) }
            }
        }
        for key in ["items", "additionalProperties", "not", "if", "then", "else"] {
            if let child = object[key] { try check(child, root: root, depth: depth + 1) }
        }
        for key in ["allOf", "anyOf", "oneOf", "prefixItems"] {
            if let value = object[key] {
                guard let children = value.array, !children.isEmpty else { throw invalid() }
                for child in children { try check(child, root: root, depth: depth + 1) }
            }
        }
        if let value = object["required"] {
            guard let children = value.array, children.allSatisfy({ $0.string != nil }),
                Set(children.compactMap(\.string)).count == children.count
            else { throw invalid() }
        }
        for key in ["minItems", "maxItems", "minLength", "maxLength", "minProperties", "maxProperties"] {
            if let value = object[key] {
                guard let count = value.number, count >= 0, count.rounded() == count else { throw invalid() }
            }
        }
        for key in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum"] {
            if let value = object[key], value.number == nil { throw invalid() }
        }
        if let value = object["multipleOf"] {
            guard let number = value.number, number > 0 else { throw invalid() }
        }
        if let value = object["uniqueItems"], value.bool == nil { throw invalid() }
        if let value = object["pattern"] {
            guard let pattern = value.string, (try? NSRegularExpression(pattern: pattern)) != nil else {
                throw invalid()
            }
        }
        if let value = object["enum"] {
            guard let choices = value.array, !choices.isEmpty else { throw invalid() }
        }
        if let fallback = object["default"], !matches(fallback, schema: schema, root: root, depth: 0) {
            throw AgentError("invalid_agent_definition", "A declared default does not satisfy its schema.")
        }
        if ["properties", "allOf", "anyOf", "oneOf"].contains(where: { object[$0] != nil }) {
            // Exercise absent object members to detect incompatible default declarations at build time.
            _ = try InputValidator.defaults(.object([:]), schema: schema, root: root, depth: 0)
        }
        if let reference = object["$ref"] {
            guard let text = reference.string, resolve(text, root: root) != nil else { throw invalid() }
        }
    }

    /// Fills absent fields only; explicit nulls and supplied values are preserved.
    public static func applyDefaults(to value: JSONValue, schema: JSONValue) throws -> JSONValue {
        try InputValidator.defaults(value, schema: schema, root: schema, depth: 0)
    }

    public static func validate(_ value: JSONValue, schema: JSONValue) throws {
        guard matches(value, schema: schema, root: schema, depth: 0) else {
            throw AgentError(
                "output_schema_validation_failed", "The final result does not match the agent output schema.")
        }
    }
    static func resolve(_ reference: String, root: JSONValue) -> JSONValue? {
        if reference == "#" { return root }
        guard reference.hasPrefix("#/") else { return nil }
        var current = root
        for part in reference.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false) {
            let token = String(part).replacingOccurrences(of: "~1", with: "/").replacingOccurrences(
                of: "~0", with: "~")
            if let next = current[token] {
                current = next
            } else if let array = current.array, let index = Int(token), String(index) == token,
                      array.indices.contains(index) {
                current = array[index]
            } else { return nil }
        }
        return current
    }
    private static func isType(_ value: JSONValue, _ type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("number", .number),
            ("boolean", .bool), ("null", .null):
            true
        case ("integer", .number(let number)): number.rounded() == number
        default: false
        }
    }
    static func matches(_ value: JSONValue, schema: JSONValue, root: JSONValue, depth: Int) -> Bool {
        guard depth < 64 else { return false }
        if let boolean = schema.bool { return boolean }
        guard let object = schema.object else { return false }
        func match(_ child: JSONValue, _ instance: JSONValue = value) -> Bool {
            matches(instance, schema: child, root: root, depth: depth + 1)
        }
        if let ref = object["$ref"]?.string {
            guard let target = resolve(ref, root: root), match(target) else { return false }
        }
        if let type = object["type"] {
            let candidates = type.string.map { [$0] } ?? type.array?.compactMap(\.string) ?? []
            if !candidates.contains(where: { isType(value, $0) }) { return false }
        }
        if let choices = object["enum"]?.array, !choices.contains(value) { return false }
        if let constant = object["const"], constant != value { return false }
        if let children = object["allOf"]?.array, !children.allSatisfy({ match($0) }) { return false }
        if let children = object["anyOf"]?.array, !children.contains(where: { match($0) }) { return false }
        if let children = object["oneOf"]?.array, children.filter({ match($0) }).count != 1 { return false }
        if let child = object["not"], match(child) { return false }
        if let condition = object["if"] {
            let branch = match(condition) ? object["then"] : object["else"]
            if let branch, !match(branch) { return false }
        }
        if let values = value.object {
            if let required = object["required"]?.array,
                !required.compactMap(\.string).allSatisfy({ values[$0] != nil })
            {
                return false
            }
            if let min = object["minProperties"]?.number, Double(values.count) < min { return false }
            if let max = object["maxProperties"]?.number, Double(values.count) > max { return false }
            let properties = object["properties"]?.object ?? [:]
            for (key, instance) in values {
                if let child = properties[key] {
                    if !match(child, instance) { return false }
                } else if let additional = object["additionalProperties"], !match(additional, instance) {
                    return false
                }
            }
        }
        if let values = value.array {
            if let min = object["minItems"]?.number, Double(values.count) < min { return false }
            if let max = object["maxItems"]?.number, Double(values.count) > max { return false }
            if object["uniqueItems"]?.bool == true {
                for index in values.indices where values[..<index].contains(values[index]) { return false }
            }
            let prefixes = object["prefixItems"]?.array ?? []
            for (index, instance) in values.enumerated() {
                if index < prefixes.count {
                    if !match(prefixes[index], instance) { return false }
                } else if let items = object["items"], !match(items, instance) {
                    return false
                }
            }
        }
        if let text = value.string {
            if let min = object["minLength"]?.number, Double(text.unicodeScalars.count) < min { return false }
            if let max = object["maxLength"]?.number, Double(text.unicodeScalars.count) > max { return false }
            if let pattern = object["pattern"]?.string,
                text.range(of: pattern, options: .regularExpression) == nil
            {
                return false
            }
        }
        if let number = value.number {
            if let min = object["minimum"]?.number, number < min { return false }
            if let max = object["maximum"]?.number, number > max { return false }
            if let min = object["exclusiveMinimum"]?.number, number <= min { return false }
            if let max = object["exclusiveMaximum"]?.number, number >= max { return false }
            if let divisor = object["multipleOf"]?.number {
                let quotient = number / divisor
                if abs(quotient - quotient.rounded()) > 1e-9 { return false }
            }
        }
        return true
    }
}
