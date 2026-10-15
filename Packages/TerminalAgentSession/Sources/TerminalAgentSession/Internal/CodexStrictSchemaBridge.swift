import Foundation

/// Strict schema converter compatible with OpenAI/Codex Draft 2020-12 strict structured output requirements.
enum CodexStrictSchemaBridge {
    static func convertToCodexStrict(schemaJSON: String) throws -> String {
        guard let data = schemaJSON.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return schemaJSON
        }
        var root = json
        if root["type"] as? String == "object" {
            root["additionalProperties"] = false
        }
        let sanitized = sanitizeNode(root)
        let outputData = try JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys])
        return String(decoding: outputData, as: UTF8.self)
    }

    private static func sanitizeNode(_ node: Any) -> Any {
        guard let dict = node as? [String: Any] else {
            if let array = node as? [Any] {
                return array.map { sanitizeNode($0) }
            }
            return node
        }

        var result: [String: Any] = [:]
        for (k, v) in dict {
            if k == "$schema" {
                continue
            }
            result[k] = sanitizeNode(v)
        }

        if let type = result["type"] as? String, type == "object" {
            result["additionalProperties"] = false
            if let props = result["properties"] as? [String: Any] {
                var requiredSet = Set((result["required"] as? [String]) ?? [])
                for propKey in props.keys {
                    requiredSet.insert(propKey)
                }
                result["required"] = Array(requiredSet).sorted()
            } else if result["required"] == nil {
                result["required"] = [String]()
            }
        }

        return result
    }
}
