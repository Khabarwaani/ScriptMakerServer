extension JSONSchema {
    static func failable(success: JSONSchema) throws -> JSONSchema {
        try JSONSchema(
            node: .union([
                .object(
                    ["status": .choices(["success"]), "output": success.node],
                    required: ["status", "output"], closed: true),
                .object(
                    [
                        "status": .choices(["failure"]),
                        "failure": .object(["reason": .scalar("string")], required: ["reason"], closed: true),
                    ],
                    required: ["status", "failure"], closed: true),
            ]))
    }
}
