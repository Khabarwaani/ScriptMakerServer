import AgentAtom
import Foundation

struct KeyPointsSuccess: Decodable {
    let output: KeyPointsSpec.Output
}

@main
struct KeyPointsExample {
    static func main() async throws {
        guard let session = AppleIntelligenceSession(configuration: .init(metadata: [.duration])) else {
            print("The Apple local model is unavailable.")
            return
        }
        let article =
            "Maya opened the library on Monday. Ravi donated forty books. The library hosts free classes on Fridays."
        let response = try await session.execute(AgenticOperation(spec: KeyPointsSpec(input: article)))
        try display(response.content)

        let unnamed = "The library opened on Monday. It has forty books. Free classes take place on Fridays."
        let stream = try await session.stream(AgenticOperation(spec: KeyPointsSpec(input: unnamed)))
        for try await snapshot in stream.snapshots {
            print(snapshot)
        }
        try display(try await stream.result().content)

        let outcome = try await session.execute(
            FailableAgenticOperation(
                spec: KeyPointsSpec(input: "Hello.")
            ))
        switch outcome.content {
        case .success(let responseString):
            let envelope = try JSONDecoder().decode(KeyPointsSuccess.self, from: Data(responseString.utf8))
            try display(envelope.output)
        case .failure(let failure):
            print("Unable to fulfill: \(failure.localizedDescription)")
        }
    }

    private static func display(_ result: AgenticResult) throws {
        switch result {
        case .success(let responseString):
            let output = try JSONDecoder().decode(KeyPointsSpec.Output.self, from: Data(responseString.utf8))
            try display(output)
        case .failure(let failure):
            print("Unable to fulfill: \(failure.localizedDescription)")
        }
    }

    private static func display(_ output: KeyPointsSpec.Output) throws {
        // Decoding and domain validation belong to the caller.
        guard output.points.count == 3 else {
            throw NSError(
                domain: "AgentAtom.KeyPointsExample", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected exactly three points."])
        }
        print(output.points.joined(separator: "\n"))
        print("People: \(output.person.joined(separator: ", "))")
    }
}
