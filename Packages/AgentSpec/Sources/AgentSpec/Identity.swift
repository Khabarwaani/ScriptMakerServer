/// Stable identity shared by all instances of one version of a specification.
public struct Identity: Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String

    public init(id: String, name: String, version: String) {
        self.id = id
        self.name = name
        self.version = version
    }
}
