extension JSONSchema {
    func allowingFailure() throws -> JSONSchema {
        try JSONSchema(
            node: .union([
                .object(
                    ["status": .choices(["success"]), "output": node],
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
