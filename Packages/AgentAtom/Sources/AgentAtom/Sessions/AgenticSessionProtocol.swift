import Foundation

public protocol AgenticSessionProtocol: Sendable {
    associatedtype SessionConfiguration: Sendable
    var configuration: SessionConfiguration { get }

    func execute<Operation: AgenticOperationProtocol>(_ operation: Operation) async -> Result<String, NSError>
    func stream<Operation: AgenticOperationProtocol>(
        _ operation: Operation
    ) async -> AsyncStream<Result<String, NSError>>
}
