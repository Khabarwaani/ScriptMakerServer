import Foundation

extension OutputValidator {
    /// Reuses the validator's assertion semantics, adding paths rather than duplicating rules.
    static func violations(_ value: JSONValue, schema: JSONValue) -> [JSONValue] {
        var result: [JSONValue] = []
        collect(value, schema: schema, root: schema, path: "", depth: 0, into: &result)
        return result.sorted {
            let left = ($0["path"]?.string ?? "", $0["keyword"]?.string ?? "")
            let right = ($1["path"]?.string ?? "", $1["keyword"]?.string ?? "")
            return left < right
        }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    private static func collect(_ value: JSONValue, schema: JSONValue, root: JSONValue,
                                path: String, depth: Int, into result: inout [JSONValue]) {
        guard depth < 64 else {
            result.append(violation(path, keyword: "$ref", expected: .string("maximum recursion depth 64"), actual: value))
            return
        }
        if schema == .bool(false) {
            result.append(violation(path, keyword: "false", expected: .bool(false), actual: value))
            return
        }
        guard let node = schema.object else { return }
        if let reference = node["$ref"]?.string, let target = resolve(reference, root: root) {
            collect(value, schema: target, root: root, path: path, depth: depth + 1, into: &result)
        }
        for child in node["allOf"]?.array ?? [] {
            collect(value, schema: child, root: root, path: path, depth: depth + 1, into: &result)
        }
        if let condition = node["if"] {
            let branch = matches(value, schema: condition, root: root, depth: depth + 1) ? node["then"] : node["else"]
            if let branch { collect(value, schema: branch, root: root, path: path, depth: depth + 1, into: &result) }
        }
        let assertions = ["type", "enum", "const", "anyOf", "oneOf", "not", "minProperties", "maxProperties",
                          "minItems", "maxItems", "uniqueItems", "minLength", "maxLength", "pattern",
                          "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf"]
        for keyword in assertions {
            guard let constraint = node[keyword] else { continue }
            if !matches(value, schema: .object([keyword: constraint]), root: root, depth: depth + 1) {
                // Composition schemas can contain defaults or examples. Do not put those values in errors.
                let expected = ["anyOf", "oneOf", "not"].contains(keyword)
                    ? .string("must satisfy \(keyword) schema constraint") : constraint
                result.append(violation(path, keyword: keyword, expected: expected, actual: value))
                if keyword == "type" { return }
            }
        }
        if let object = value.object {
            let properties = node["properties"]?.object ?? [:]
            for key in node["required"]?.array?.compactMap(\.string) ?? [] where object[key] == nil {
                var expected: [String: JSONValue] = ["required": .bool(true)]
                let property = properties[key]
                let referenced = property?["$ref"]?.string.flatMap { resolve($0, root: root) }
                if let type = property?["type"] ?? referenced?["type"] { expected["type"] = type }
                result.append(violation(pointer(path, key), keyword: "required", expected: .object(expected), actual: nil))
            }
            for key in object.keys.sorted() {
                if let child = properties[key] {
                    collect(object[key]!, schema: child, root: root, path: pointer(path, key), depth: depth + 1, into: &result)
                } else if let additional = node["additionalProperties"] {
                    if additional == .bool(false) {
                        result.append(violation(pointer(path, key), keyword: "additionalProperties", expected: .bool(false), actual: object[key]))
                    } else {
                        collect(object[key]!, schema: additional, root: root, path: pointer(path, key), depth: depth + 1, into: &result)
                    }
                }
            }
        }
        if let values = value.array {
            let prefixes = node["prefixItems"]?.array ?? []
            for (index, item) in values.enumerated() {
                let child = index < prefixes.count ? prefixes[index] : node["items"] ?? .bool(true)
                collect(item, schema: child, root: root, path: pointer(path, String(index)), depth: depth + 1, into: &result)
            }
        }
    }

    static func pointer(_ path: String, _ key: String) -> String {
        path + "/" + key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    private static func violation(_ path: String, keyword: String, expected: JSONValue, actual: JSONValue?) -> JSONValue {
        let field = path.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let decoded = field.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        let message = keyword == "required"
            ? "Required field '\(decoded)' is missing at '\(path)' and has no default."
            : "Field at '\(path)' fails '\(keyword)' validation."
        let type: String
        switch actual {
        case nil: type = "missing"
        case .object?: type = "object"
        case .array?: type = "array"
        case .string?: type = "string"
        case .number?: type = "number"
        case .bool?: type = "boolean"
        case .null?: type = "null"
        }
        return .object(["path": .string(path), "field": .string(decoded), "keyword": .string(keyword),
                        "message": .string(message), "expected": expected, "actual": .string(type)])
    }
}
