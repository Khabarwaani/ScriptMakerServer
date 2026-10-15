import AgentAtom
import Foundation
import Testing

struct SessionConfigurationTests {
    @Test
    func optionalMetadataDistinguishesAbsentFromZero() {
        let operation = TestSession()
        let id = UUID()
        let absent = AgenticExecutionMetadata(operationID: ObjectIdentifier(operation), executionID: id)
        let zero = AgenticExecutionMetadata(operationID: ObjectIdentifier(operation), executionID: id, promptTokens: 0, completionTokens: 0)
        #expect(absent.promptTokens == nil)
        #expect(absent.completionTokens == nil)
        #expect(zero.promptTokens == 0)
        #expect(zero.completionTokens == 0)
        #expect(absent != zero)
        let fields: AgenticExecutionMetadata.Fields = [.modelIdentifier, .duration, .tokenUsage]
        #expect(fields.subtracting(.duration) == [.modelIdentifier, .tokenUsage])
        #expect(AgenticExecutionMetadata.Fields().isEmpty)
    }

    #if canImport(FoundationModels) && (os(macOS) || os(iOS) || os(visionOS))
    @Test(arguments: [Double.nan, -.infinity, -1, 0, 0.5, 1, 2, .infinity])
    func appleTemperatureBounds(temperature: Double) {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let configuration = AppleIntelligenceSession.Configuration(temperature: temperature)
            let expected = temperature.isNaN ? 1 : min(max(temperature, 0), 1)
            #expect(configuration.temperature == expected)
            #expect(configuration.metadata.isEmpty)
        }
    }

    @Test
    func appleMetadataConfiguration() {
        if #available(macOS 26, iOS 26, visionOS 26, *) {
            let configuration = AppleIntelligenceSession.Configuration(metadata: [.duration, .tokenUsage])
            #expect(configuration.metadata == [.duration, .tokenUsage])
            #expect(configuration.temperature == 1)
        }
    }
    #endif
}
