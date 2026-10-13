import Foundation

/// Codex's strict transport requires every closed object's property. Missing
/// optional values travel as null; the immutable domain schema stays authoritative.
enum CodexOutputSchema {
    private enum Unsupported: Error { case shape }
    static func make(_ schema: JSONValue) -> JSONValue? { try? convert(schema, depth: 0) }
    static let feasibilitySchema: JSONValue = .object([
        "type": .string("object"), "additionalProperties": .bool(false),
        "required": .array([.string("reason")]),
        "properties": .object(["reason": .object(["type": .string("string")]),
            "code": .object(["type": .string("string")]), "message": .object(["type": .string("string")])]),
    ])
    /// Codex forbids a root oneOf/anyOf. A private transport envelope permits
    /// either domain output or the master's feasibility error without changing
    /// the public result. Both fresh and persistent adapters use this bridge.
    static func executionSchema(_ domain: JSONValue) -> JSONValue? {
        guard (try? OutputValidator.validate(.null, schema: domain)) == nil,
              let strict = make(domain), let error = make(feasibilitySchema) else { return nil }
        return .object(["type": .string("object"), "additionalProperties": .bool(false),
            "$defs": .object(["agent": relocateReferences(strict)]),
            "required": .array([.string("output"), .string("error")]),
            "properties": .object([
                "output": .object(["anyOf": .array([.object(["$ref": .string("#/$defs/agent")]), .object(["type": .string("null")])])]),
                "error": .object(["anyOf": .array([error, .object(["type": .string("null")])])]),
            ])])
    }
    private static func relocateReferences(_ value: JSONValue) -> JSONValue {
        if let array = value.array { return .array(array.map(relocateReferences)) }
        guard var object = value.object else { return value }
        for (key, child) in object {
            if key == "$ref", let reference = child.string, reference == "#" || reference.hasPrefix("#/") {
                object[key] = .string("#/$defs/agent" + reference.dropFirst())
            } else if !["const", "enum", "examples", "default"].contains(key) {
                object[key] = relocateReferences(child)
            }
        }
        return .object(object)
    }
    static func executionResult(_ value: JSONValue, schema: JSONValue) throws -> JSONValue {
        guard let object = value.object, Set(object.keys) == ["output", "error"],
              let output = object["output"], let error = object["error"] else {
            throw AgentError("invalid_final_json", "Codex did not return a complete native result envelope.")
        }
        if error == .null, output != .null { return normalize(output, schema: schema) }
        if output == .null, error != .null {
            let normalized = normalize(error, schema: feasibilitySchema)
            try OutputValidator.validate(normalized, schema: feasibilitySchema)
            return .object(["error": normalized])
        }
        throw AgentError("invalid_final_json", "Codex returned conflicting or empty native results.")
    }
    private static func convert(_ schema: JSONValue, depth: Int) throws -> JSONValue {
        guard depth < 64, var object = schema.object else { throw Unsupported.shape }
        for key in ["$defs", "definitions"] {
            if let definitions = object[key]?.object {
                object[key] = .object(try definitions.mapValues { try convert($0, depth: depth + 1) })
            }
        }
        // Native strict output does not support unrestricted dynamic dictionaries
        // or allOf/oneOf. Keep these on prompt + authoritative server validation.
        guard object["allOf"] == nil, object["oneOf"] == nil else { throw Unsupported.shape }
        if let types = object["type"]?.array, types.count > 1 {
            var branches: [JSONValue] = []
            for value in types {
                guard let type = value.string else { throw Unsupported.shape }
                var branch = object
                branch["type"] = .string(type)
                branch["$defs"] = nil; branch["definitions"] = nil
                if type != "object" { for key in ["properties", "required", "additionalProperties"] { branch[key] = nil } }
                if type != "array" { for key in ["items", "minItems", "maxItems", "prefixItems", "contains"] { branch[key] = nil } }
                if type != "string" { for key in ["pattern", "minLength", "maxLength"] { branch[key] = nil } }
                if type != "number" && type != "integer" { for key in ["minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"] { branch[key] = nil } }
                branches.append(try convert(.object(branch), depth: depth + 1))
            }
            var union: [String: JSONValue] = ["anyOf": .array(branches)]
            for key in ["description", "$defs", "definitions"] { union[key] = object[key] }
            return .object(union)
        }
        if object["type"]?.string == "object" || object["properties"] != nil {
            guard object["additionalProperties"]?.bool == false else { throw Unsupported.shape }
            let properties = object["properties"]?.object ?? [:]
            let required = Set(object["required"]?.array?.compactMap(\.string) ?? [])
            var converted: [String: JSONValue] = [:]
            for (key, property) in properties {
                let value = try convert(property, depth: depth + 1)
                converted[key] = required.contains(key) ? value : .object([
                    "anyOf": .array([value, .object(["type": .string("null")])]),
                ])
            }
            object["properties"] = .object(converted)
            object["required"] = .array(properties.keys.sorted().map(JSONValue.string))
        }
        if let items = object["items"] { object["items"] = try convert(items, depth: depth + 1) }
        if let choices = object["anyOf"]?.array {
            object["anyOf"] = .array(try choices.map { try convert($0, depth: depth + 1) })
        }
        return .object(object)
    }
    static func normalize(_ value: JSONValue, schema: JSONValue) -> JSONValue {
        normalize(value, schema: schema, root: schema, depth: 0)
    }
    private static func resolved(_ schema: JSONValue, root: JSONValue) -> JSONValue {
        guard let reference = schema["$ref"]?.string, reference.hasPrefix("#/") else { return schema }
        var node = root
        for part in reference.dropFirst(2).split(separator: "/") {
            let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            guard let next = node[key] else { return schema }
            node = next
        }
        return node
    }
    private static func acceptsNull(_ schema: JSONValue, root: JSONValue) -> Bool {
        var object = resolved(schema, root: root).object ?? [:]
        if let definitions = root["$defs"] { object["$defs"] = definitions }
        do { try OutputValidator.validate(.null, schema: .object(object)); return true }
        catch { return false }
    }
    private static func normalize(_ value: JSONValue, schema: JSONValue, root: JSONValue, depth: Int) -> JSONValue {
        guard depth < 64 else { return value }
        let node = resolved(schema, root: root)
        if var object = value.object, let properties = node["properties"]?.object {
            let required = Set(node["required"]?.array?.compactMap(\.string) ?? [])
            for (key, property) in properties {
                guard let field = object[key] else { continue }
                if field == .null && !required.contains(key) && !acceptsNull(property, root: root) { object[key] = nil }
                else { object[key] = normalize(field, schema: property, root: root, depth: depth + 1) }
            }
            return .object(object)
        }
        if let array = value.array, let itemSchema = node["items"] {
            return .array(array.map { normalize($0, schema: itemSchema, root: root, depth: depth + 1) })
        }
        if let choices = node["anyOf"]?.array {
            for choice in choices {
                let candidate = normalize(value, schema: choice, root: root, depth: depth + 1)
                if (try? OutputValidator.validate(candidate, schema: resolved(choice, root: root))) != nil { return candidate }
            }
        }
        return value
    }
}
