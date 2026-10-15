public actor FailableAgenticOperation<Specification: Spec, Session: AgenticSessionProtocol>: AgenticOperationProtocol, OperationLifecycle {
    public typealias Result = Swift.Result<String, AgenticError>

    public let spec: Specification
    public internal(set) var state: OperationState = .ready
    let session: Session
    let strategy = FailableOperationStrategy()
    var task: Task<Swift.Result<String, AgenticError>, Never>?

    public init(spec: Specification, session: Session) {
        self.spec = spec
        self.session = session
    }

    public func execute() async -> Result {
        await start()
    }
}
