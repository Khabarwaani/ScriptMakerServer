import Foundation

extension AgenticOperationProtocol {
    public func result(from response: String) throws -> Result<String, NSError> {
        .success(response)
    }
}
