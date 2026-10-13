import Foundation

/// Codex's strict transport requires every closed object's property. Missing
/// optional values travel as null; the immutable domain schema stays authoritative.
enum CodexOutputSchema {
    private enum Unsupported: Error { case shape }
    static func make(_ schema: JSONValue) -> JSONValue? { try? convert(schema, depth: 0) }
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
