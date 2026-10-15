#if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
    internal import FoundationModels

    @available(macOS 26, iOS 26, visionOS 26, *)
    enum AppleSchemaTranslator {
        static func translate(_ schema: JSONSchema) throws -> GenerationSchema {
            var counter = 0
            let root = try translate(schema.node, counter: &counter)
            do {
                return try GenerationSchema(root: root, dependencies: [])
            } catch {
                throw AgenticSessionError.unsupportedSchema(reason: "Apple could not construct the generation schema.")
            }
        }

        private static func translate(
            _ node: JSONSchema.SchemaNode,
            counter: inout Int
        ) throws -> DynamicGenerationSchema {
            counter += 1
            let name = "AgentAtomType\(counter)"
            switch node {
            case .scalar(let type, let format, let encoding):
                guard format == nil, encoding == nil else {
                    throw unsupported("Formats and content encodings are not supported.")
                }
                switch type {
                case "string": return DynamicGenerationSchema(type: String.self)
                case "boolean": return DynamicGenerationSchema(type: Bool.self)
                case "integer": return DynamicGenerationSchema(type: Int.self)
                case "number": return DynamicGenerationSchema(type: Double.self)
                case "null": return try nullSchema()
                default: throw unsupported("Unknown primitive type.")
                }
            case .choices(let values):
                return DynamicGenerationSchema(name: name, anyOf: values)
            case .array(let element):
                return DynamicGenerationSchema(arrayOf: try translate(element, counter: &counter))
            case .object(let properties, let required, _):
                let fields = try properties.sorted { $0.key < $1.key }.map { key, value in
                    let isOptional = !required.contains(key)
                    // Omission is a valid subset for optional properties on the OS 26 baseline.
                    var node = value
                    if isOptional, case .nullable(let wrapped) = node { node = wrapped }
                    return DynamicGenerationSchema.Property(
                        name: key, schema: try translate(node, counter: &counter), isOptional: isOptional
                    )
                }
                return DynamicGenerationSchema(name: name, properties: fields)
            case .union(let alternatives):
                return DynamicGenerationSchema(
                    name: name, anyOf: try alternatives.map { try translate($0, counter: &counter) })
            case .nullable(let wrapped):
                return DynamicGenerationSchema(
                    name: name, anyOf: [try translate(wrapped, counter: &counter), try nullSchema()])
            case .dictionary:
                throw unsupported("Dictionaries with arbitrary keys are not supported.")
            }
        }

        private static func nullSchema() throws -> DynamicGenerationSchema {
            #if compiler(>=6.3)
                if #available(macOS 26.4, iOS 26.4, visionOS 26.4, *) { return .null }
            #endif
            throw unsupported("Required null values need an SDK and OS supporting explicit null generation.")
        }

        private static func unsupported(_ reason: String) -> AgenticSessionError {
            .unsupportedSchema(reason: reason)
        }
    }
#endif
