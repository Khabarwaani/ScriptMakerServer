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

enum ExampleError: Error { case wrongPointCount }

@main
struct KeyPointsExample {
    static func main() async throws {
        let session = try AppleIntelligenceSession(configuration: .init(metadata: [.duration]))
        let article =
            "Maya opened the library on Monday. Ravi donated forty books. The library hosts free classes on Fridays."
        let response = try await session.execute(AgenticOperation(spec: KeyPointsSpec(input: article)))
        try display(response.content)

        let unnamed = "The library opened on Monday. It has forty books. Free classes take place on Fridays."
        let stream = try await session.stream(AgenticOperation(spec: KeyPointsSpec(input: unnamed)))
        for try await snapshot in stream.snapshots {
            if case .text(let text) = snapshot { print(text) }
        }
        try display(try await stream.result().content)

        let outcome = try await session.execute(
            FailableAgenticOperation(
                spec: KeyPointsSpec(input: "Hello."),
                failureGuidance: "Return failure if the input cannot support three meaningful points."
            ))
        switch outcome.content {
        case .success(let output): try display(output)
        case .failure(let failure): print("Unable to fulfill: \(failure.reason)")
        }
    }

    private static func display(_ output: KeyPointsSpec.Output) throws {
        // Domain validation belongs to the caller.
        guard output.points.count == 3 else { throw ExampleError.wrongPointCount }
        print(output.points.joined(separator: "\n"))
        print("People: \(output.person.joined(separator: ", "))")
    }
}
