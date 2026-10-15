public protocol ModelledSpec<Input, Output>: Spec {
    associatedtype Input: Encodable & Sendable
    associatedtype Output: Decodable & Sendable

    var input: Input { get }
    var output: Output? { get set }
}
