import AgentAtom

struct KeyPointsOutput: Decodable, Sendable, Equatable {
    let points: [String]
    let person: [String]
}

struct KeyPointsSpec: ModelledSpec {
    static let identity = Identity(id: "key-points", name: "Key Points", version: "1")
    static let role = "Extract factual key points and explicitly named people."
    let instructions = """
        Extract exactly three distinct factual points supported by the input.
        A request is feasible only when the input explicitly supplies at least three
        distinct facts. Greetings, a topic alone, and prose with only one or two
        facts are insufficient. Never invent facts, repeat a fact, or reduce the count.
        For example, "Mira planted an oak. Leon watered it. Mira built a fence."
        supplies three facts and is sufficient. "Mira planted an oak. Leon watered it."
        supplies only two facts: choose Failure, never a two-point Success.
        "Good morning!" supplies no facts
        and is insufficient. When a failure alternative is available, choose it
        for insufficient input; empty arrays or fewer than three points are not success.
        Extract distinct explicitly named people or characters in first-appearance
        order. Use an empty person array when the prose contains no named people.
        """
    let input: String
    var output: KeyPointsOutput?

    static let namedInput = "Asha opened the library on Monday. Ben donated twenty books. Asha hosted a reading session on Friday."
    static let insufficientInput = "Asha opened the library. Ben donated books."
    static let unnamedInput = "The library opened on Monday. Twenty books were donated. A reading session took place on Friday."
    static let namedJSON = #"{"points":["Asha opened the library on Monday.","Ben donated twenty books.","Asha hosted a reading session on Friday."],"person":["Asha","Ben"]}"#
    static let unnamedJSON = #"{"points":["The library opened on Monday.","Twenty books were donated.","A reading session took place on Friday."],"person":[]}"#
    static let failureJSON = #"{"domain":"AgentAtom.Operation","code":422,"reason":"The input does not support three meaningful points."}"#
}
