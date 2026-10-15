public actor StreamingAgenticOperation<Specification: Spec, Session: AgenticSessionProtocol>: AgenticOperationProtocol, OperationLifecycle {
    public typealias Result = AsyncStream<Swift.Result<String, AgenticError>>

    public let spec: Specification
    public internal(set) var state: OperationState = .ready
    let session: Session
    let strategy = JSONOperationStrategy()
    var task: Task<Void, Never>?

    public init(spec: Specification, session: Session) {
        self.spec = spec
        self.session = session
    }

    public func execute() async -> Result {
        await start()
    }
}
