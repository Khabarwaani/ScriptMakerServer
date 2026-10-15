import AgentAtom

struct KeyPointsSpec: ModelledSpec {
    struct Output: Decodable, Sendable {
        let points: [String]
        let person: [String]
    }

    static let identity = Identity(id: "key-points", name: "Key points", version: "1.0.0")
    static let role = "Extract factual key points and explicitly named people from the input."
    let input: String
    var output: Output?
    let instructions = """
        Return exactly three concise points supported by the input. Do not invent facts.
        List distinct named people or characters in first-appearance order in person.
        Use an empty person array when nobody is named.
        """
}
