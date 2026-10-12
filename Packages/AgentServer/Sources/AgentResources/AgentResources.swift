import Foundation

/// Build-time snapshots of public agent definitions and runtime assets.
/// Runtime discovery itself remains in AgentCore and accepts any configured root.
public enum AgentResources {
    public static var root: URL { Bundle.module.resourceURL! }
}
