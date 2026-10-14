public protocol Spec: Sendable {
    static var identity: Identity { get }

    var inputJSON: JSONString { get }
    static var outputSchema: JSONSchema { get }
    static var role: String { get }
    var instructions: String { get }
}
