import Foundation
import Testing
@testable import AudioInput
import SpeechCore

// MARK: - Mock Services

private actor MockTranscriptionService: TranscriptionService {
    nonisolated let id: String
    var isAvailable: Bool

    init(id: String, isAvailable: Bool = true) {
        self.id = id
        self.isAvailable = isAvailable
    }

    func start() throws(SpeechCoreError) -> AsyncThrowingStream<TranscriptionSegment, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func stop() async throws(SpeechCoreError) {}
}

// MARK: - Tests

@Suite("TranscriberRegistry provider switching")
struct TranscriberRegistryProviderTests {

    @Test("Empty registry returns no available services")
    func emptyRegistry() async {
        let registry = TranscriberRegistry()
        let services = await registry.availableServices()
        #expect(services.isEmpty)
    }

    @Test("Registered available service appears in availableServices")
    func singleAvailableService() async {
        let registry = TranscriberRegistry()
        let svc = MockTranscriptionService(id: "svc-a", isAvailable: true)
        await registry.register(svc)

        let services = await registry.availableServices()
        #expect(services.count == 1)
        #expect(services.first?.id == "svc-a")
    }

    @Test("Unavailable service is excluded from availableServices")
    func unavailableServiceExcluded() async {
        let registry = TranscriberRegistry()
        let available = MockTranscriptionService(id: "available", isAvailable: true)
        let unavailable = MockTranscriptionService(id: "unavailable", isAvailable: false)
        await registry.register(available)
        await registry.register(unavailable)

        let services = await registry.availableServices()
        #expect(services.count == 1)
        #expect(services.first?.id == "available")
    }

    @Test("service(for:) returns registered service by ID")
    func serviceForId() async {
        let registry = TranscriberRegistry()
        let svc = MockTranscriptionService(id: "target-id")
        await registry.register(svc)

        let found = await registry.service(for: "target-id")
        #expect(found?.id == "target-id")
    }

    @Test("service(for:) returns nil for unregistered ID")
    func serviceForUnknownId() async {
        let registry = TranscriberRegistry()
        let found = await registry.service(for: "nonexistent")
        #expect(found == nil)
    }

    @Test("Registering same ID twice overwrites previous service")
    func overwriteDuplicateId() async {
        let registry = TranscriberRegistry()
        let first = MockTranscriptionService(id: "dup", isAvailable: false)
        let second = MockTranscriptionService(id: "dup", isAvailable: true)
        await registry.register(first)
        await registry.register(second)

        let services = await registry.availableServices()
        #expect(services.count == 1)
        #expect(services.first?.id == "dup")
    }

    @Test("Selected service ID persists in AppSettings")
    func selectedServiceIdPersistedInSettings() {
        var settings = AppSettings()
        #expect(settings.selectedTranscriptionServiceId == nil)

        settings.selectedTranscriptionServiceId = "com.speech-suite.speech-analyzer"
        #expect(settings.selectedTranscriptionServiceId == "com.speech-suite.speech-analyzer")
    }

    @Test("AppSettings selectedTranscriptionServiceId round-trips through JSON")
    func settingsRoundTrip() throws {
        var settings = AppSettings()
        settings.selectedTranscriptionServiceId = "com.speech-suite.speech-analyzer"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.selectedTranscriptionServiceId == "com.speech-suite.speech-analyzer")
    }

    @Test("AppSettings selectedTranscriptionServiceId defaults to nil when key is absent")
    func settingsDefaultsToNilWhenKeyAbsent() throws {
        // Encode default settings (which includes selectedTranscriptionServiceId == nil),
        // then strip the key to simulate an older JSON schema.
        let defaults = AppSettings()
        let data = try JSONEncoder().encode(defaults)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "selectedTranscriptionServiceId")

        let strippedData = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: strippedData)
        #expect(decoded.selectedTranscriptionServiceId == nil)
    }
}
