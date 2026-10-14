public protocol Spec: Sendable {
    static var identity: Identity { get }

    var inputJSON: JSONString { get }
    var outputSchema: JSONSchema { get }
    var role: String { get }
    var instructions: String { get }
}
