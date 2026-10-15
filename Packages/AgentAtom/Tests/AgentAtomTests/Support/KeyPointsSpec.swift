import AgentAtom

struct KeyPointsOutput: Decodable, Sendable, Equatable {
    let points: [String]
    let person: [String]
}

struct KeyPointsSpec: ModelledSpec {
    static let identity = Identity(id: "key-points", name: "Key Points", version: "1")
    static let role = "Extract factual key points and explicitly named people."
    let instructions = """
        Return a JSON object containing actual extracted values, not a JSON schema.
        Your entire response must start with { and end with }. Do not emit backticks,
        Markdown, explanations, properties, required, type, or any schema keywords.
        For success, use exactly this shape:
        {"points":["first supported fact","second supported fact","third supported fact"],"person":["first name","second name"]}
        Return exactly three distinct, concise points supported by the input.
        Extract explicitly named people or characters in first-appearance order,
        without duplicates. Return an empty person array if no names appear.
        Do not invent facts or names. If failure is allowed and the input cannot
        support three meaningful points, use the supplied failure format.
        """
    let input: String
    var output: KeyPointsOutput?

    static let namedInput = "Asha opened the library on Monday. Ben donated twenty books. Asha hosted a reading session on Friday."
    static let unnamedInput = "The library opened on Monday. Twenty books were donated. A reading session took place on Friday."
    static let namedJSON = #"{"points":["Asha opened the library on Monday.","Ben donated twenty books.","Asha hosted a reading session on Friday."],"person":["Asha","Ben"]}"#
    static let unnamedJSON = #"{"points":["The library opened on Monday.","Twenty books were donated.","A reading session took place on Friday."],"person":[]}"#
    static let failureJSON = #"{"domain":"AgentAtom.Operation","code":422,"reason":"The input does not support three meaningful points."}"#
}
