import Foundation
import Testing
import JSONEcho

@Test func definitionResourcesAreComplete() throws {
    for version in JSONEchoDefinition.versions {
        let root = try JSONEchoDefinition.directory(version: version)
        for name in ["role.md", "instructions.md", "output.schema.json"] {
            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path))
        }
        let schema = try Data(contentsOf: root.appendingPathComponent("output.schema.json"))
        #expect(try JSONSerialization.jsonObject(with: schema) is [String: Any])
    }
}
