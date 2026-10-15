import Foundation

public protocol AgenticSessionProtocol: Sendable {
    associatedtype SessionConfiguration: Sendable
    associatedtype SessionError: Error = AgenticSessionError
    var configuration: SessionConfiguration { get }

    func execute(_ operation: any AgenticOperationProtocol) async throws(SessionError) -> (
        content: Result<String, NSError>, metadata: AgenticExecutionMetadata?
    )
    func stream(_ operation: any AgenticOperationProtocol) async throws(SessionError) -> (
        snapshots: AsyncThrowingStream<String, any Error>,
        result: Task<(content: Result<String, NSError>, metadata: AgenticExecutionMetadata?), any Error>
    )
}
