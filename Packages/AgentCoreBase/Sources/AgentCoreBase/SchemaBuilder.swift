import Foundation

/// Protocol for Swift models that can generate Draft 2020-12 JSON Schema representations.
public protocol JSONSchemaConvertible: Sendable {
    static func schema() -> SchemaDefinition
}

/// Represents an individual property in a JSON Schema object.
public struct SchemaProperty: Sendable {
    public let name: String
    public let type: String
    public let description: String?
    public let defaultValue: JSONValue?
    public let required: Bool
    public let minimum: Double?
    public let maximum: Double?
    public let enumValues: [String]?
    public let nestedSchema: SchemaDefinition?
    public let itemsSchema: SchemaDefinition?
    public let minItems: Int?
    public let maxItems: Int?

    public init(
        name: String,
        type: String,
        description: String? = nil,
        defaultValue: JSONValue? = nil,
        required: Bool = false,
        minimum: Double? = nil,
        maximum: Double? = nil,
        enumValues: [String]? = nil,
        nestedSchema: SchemaDefinition? = nil,
        itemsSchema: SchemaDefinition? = nil,
        minItems: Int? = nil,
        maxItems: Int? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
        self.required = required
        self.minimum = minimum
        self.maximum = maximum
        self.enumValues = enumValues
        self.nestedSchema = nestedSchema
        self.itemsSchema = itemsSchema
        self.minItems = minItems
        self.maxItems = maxItems
    }
}

/// Represents a Draft 2020-12 JSON Schema object.
public struct SchemaDefinition: Sendable {
    public let title: String?
    public let description: String?
    public let properties: [SchemaProperty]
    public let additionalProperties: Bool

    public init(
        title: String? = nil,
        description: String? = nil,
        properties: [SchemaProperty] = [],
        additionalProperties: Bool = false
    ) {
        self.title = title
        self.description = description
        self.properties = properties
        self.additionalProperties = additionalProperties
    }

    /// Converts this schema definition into a Draft 2020-12 JSONValue.
    public func toJSONValue() -> JSONValue {
        var propMap: [String: JSONValue] = [:]
        var requiredList: [JSONValue] = []

        for prop in properties {
            var propObj: [String: JSONValue] = ["type": .string(prop.type)]
            if let desc = prop.description {
                propObj["description"] = .string(desc)
            }
            if let def = prop.defaultValue {
                propObj["default"] = def
            }
            if let min = prop.minimum {
                propObj["minimum"] = .number(min)
            }
            if let max = prop.maximum {
                propObj["maximum"] = .number(max)
            }
            if let enums = prop.enumValues {
                propObj["enum"] = .array(enums.map { .string($0) })
            }
            if let nested = prop.nestedSchema {
                let nestedVal = nested.toJSONValue()
                if let dict = nestedVal.object {
                    for (k, v) in dict where k != "$schema" {
                        propObj[k] = v
                    }
                }
            }
            if let items = prop.itemsSchema {
                let itemsVal = items.toJSONValue()
                if var dict = itemsVal.object {
                    dict.removeValue(forKey: "$schema")
                    propObj["items"] = .object(dict)
                }
            }
            if let minItems = prop.minItems {
                propObj["minItems"] = .number(Double(minItems))
            }
            if let maxItems = prop.maxItems {
                propObj["maxItems"] = .number(Double(maxItems))
            }

            propMap[prop.name] = .object(propObj)
            if prop.required {
                requiredList.append(.string(prop.name))
            }
        }

        var schemaObj: [String: JSONValue] = [
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "type": .string("object"),
            "properties": .object(propMap),
            "additionalProperties": .bool(additionalProperties)
        ]

        if let title = title {
            schemaObj["title"] = .string(title)
        }
        if let desc = description {
            schemaObj["description"] = .string(desc)
        }
        if !requiredList.isEmpty {
            schemaObj["required"] = .array(requiredList)
        }

        return .object(schemaObj)
    }

    /// Serializes the schema definition to pretty-printed JSON text.
    public func toJSONString() throws -> String {
        let val = toJSONValue()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(val)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
