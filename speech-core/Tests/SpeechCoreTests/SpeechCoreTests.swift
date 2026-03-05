import Foundation
import Testing
@testable import SpeechCore

// MARK: - TranscriptionSegment

@Test func segmentCodableRoundTrip() throws {
    let original = try TranscriptionSegment(
        text: "Hello",
        startTime: 1.0,
        endTime: 2.5,
        confidence: 0.9,
        speaker: "Alice"
    )
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TranscriptionSegment.self, from: data)
    #expect(decoded == original)
}

@Test func segmentCodableRoundTripWithNils() throws {
    let original = try TranscriptionSegment(text: "Hi", startTime: 0, endTime: 1)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TranscriptionSegment.self, from: data)
    #expect(decoded == original)
}

@Test func segmentSpeakerIsOptional() throws {
    let seg = try TranscriptionSegment(text: "Hi", startTime: 0, endTime: 1)
    #expect(seg.speaker == nil)
}

@Test func segmentStoresSpeaker() throws {
    let seg = try TranscriptionSegment(text: "Hi", startTime: 0, endTime: 1, speaker: "Bob")
    #expect(seg.speaker == "Bob")
}

@Test func segmentDecodeInvalidTimeRangeThrows() {
    let json = #"{"text":"Bad","startTime":5.0,"endTime":1.0}"#
    let data = Data(json.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(TranscriptionSegment.self, from: data)
    }
}

@Test func segmentDecodeInvalidConfidenceThrows() {
    let json = #"{"text":"Bad","startTime":0,"endTime":1,"confidence":2.0}"#
    let data = Data(json.utf8)
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(TranscriptionSegment.self, from: data)
    }
}

@Test func segmentStoresFields() throws {
    let seg = try TranscriptionSegment(
        text: "Hello",
        startTime: 1.0,
        endTime: 2.5,
        confidence: 0.9
    )
    #expect(seg.text == "Hello")
    #expect(seg.startTime == 1.0)
    #expect(seg.endTime == 2.5)
    #expect(seg.confidence == 0.9)
    #expect(seg.duration == 1.5)
}

@Test func segmentConfidenceIsOptional() throws {
    let seg = try TranscriptionSegment(text: "Hi", startTime: 0, endTime: 1)
    #expect(seg.confidence == nil)
}

@Test func segmentZeroDurationIsValid() throws {
    let seg = try TranscriptionSegment(text: "", startTime: 1.0, endTime: 1.0)
    #expect(seg.duration == 0)
}

@Test func segmentInvalidTimeRangeThrows() {
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: 2.0, endTime: 1.0)
    } throws: { error in
        if case SpeechCoreError.invalidTimeRange = error { true } else { false }
    }
}

@Test func segmentNegativeStartTimeThrows() {
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: -1.0, endTime: 0.0)
    } throws: { error in
        if case SpeechCoreError.invalidTimeRange = error { true } else { false }
    }
}

@Test func segmentInfiniteTimeThrows() {
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: .infinity, endTime: .infinity)
    } throws: { error in
        if case SpeechCoreError.invalidTimeRange = error { true } else { false }
    }
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: .nan, endTime: 1.0)
    } throws: { error in
        if case SpeechCoreError.invalidTimeRange = error { true } else { false }
    }
}

@Test func segmentConfidenceOutOfRangeThrows() {
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: 0, endTime: 1, confidence: 1.5)
    } throws: { error in
        if case SpeechCoreError.invalidConfiguration = error { true } else { false }
    }
    #expect {
        try TranscriptionSegment(text: "Bad", startTime: 0, endTime: 1, confidence: -0.1)
    } throws: { error in
        if case SpeechCoreError.invalidConfiguration = error { true } else { false }
    }
}

// MARK: - SpeechCoreError

@Test func errorDescriptionIsNonNil() {
    struct StubError: Error, Sendable {}

    let cases: [SpeechCoreError] = [
        .fileNotFound(path: "/tmp/a.wav"),
        .unsupportedFormat(path: "/tmp/b.opus"),
        .permissionDenied(permission: "microphone"),
        .engineUnavailable(engine: "Apple Speech", requiredOS: "macOS 15"),
        .recognitionFailed(underlying: StubError()),
        .timeout,
        .emptyResult,
        .invalidTimeRange,
        .invalidConfiguration("bad"),
        .alreadyStarted,
        .invalidInputURL,
    ]
    for error in cases {
        #expect(error.errorDescription != nil, "errorDescription should be non-nil for \(error)")
    }
}

@Test func recognitionFailedIncludesUnderlyingDescription() {
    struct EngineError: Error, Sendable, LocalizedError {
        var errorDescription: String? { "Model loading failed" }
    }
    let error = SpeechCoreError.recognitionFailed(underlying: EngineError())
    let description = error.errorDescription ?? ""
    #expect(description.contains("Model loading failed"),
            "errorDescription should include underlying error description, got: \(description)")
}

// MARK: - HallucinationFilter

@Test func filterRemovesShortSegments() throws {
    let segments = try [
        TranscriptionSegment(text: "Hi", startTime: 0.0, endTime: 0.2),
        TranscriptionSegment(text: "Hello world", startTime: 1.0, endTime: 2.0),
        TranscriptionSegment(text: "Ok", startTime: 3.0, endTime: 3.4),
        TranscriptionSegment(text: "Good morning", startTime: 4.0, endTime: 5.5),
    ]
    let filter = try HallucinationFilter(minimumDuration: 0.5)
    let result = filter.filter(segments)
    #expect(result.count == 2)
    #expect(result[0].text == "Hello world")
    #expect(result[1].text == "Good morning")
}

@Test func filterKeepsAllWhenNoneShort() throws {
    let segments = try [
        TranscriptionSegment(text: "Hello", startTime: 0.0, endTime: 1.0),
        TranscriptionSegment(text: "World", startTime: 1.0, endTime: 2.0),
    ]
    let filter = try HallucinationFilter(minimumDuration: 0.5)
    let result = filter.filter(segments)
    #expect(result.count == 2)
}

@Test func filterWithDefaultThreshold() throws {
    let short = try TranscriptionSegment(text: "Hi", startTime: 0.0, endTime: 0.4)
    let normal = try TranscriptionSegment(text: "Hello", startTime: 1.0, endTime: 2.0)
    let filter = try HallucinationFilter()
    let result = filter.filter([short, normal])
    #expect(result.count == 1)
    #expect(result[0].text == "Hello")
}

@Test func filterInvalidMinimumDurationThrows() {
    #expect(throws: SpeechCoreError.self) {
        try HallucinationFilter(minimumDuration: -1.0)
    }
    #expect(throws: SpeechCoreError.self) {
        try HallucinationFilter(minimumDuration: .nan)
    }
    #expect(throws: SpeechCoreError.self) {
        try HallucinationFilter(minimumDuration: .infinity)
    }
}

@Test func filterBoundaryDurationIsKept() throws {
    // duration == minimumDuration は除外しない（>= の境界）
    let seg = try TranscriptionSegment(text: "Boundary", startTime: 0.0, endTime: 0.5)
    let filter = try HallucinationFilter(minimumDuration: 0.5)
    let result = filter.filter([seg])
    #expect(result.count == 1)
}

// MARK: - TranscriberRegistry

private actor MockService: TranscriptionService {
    nonisolated let id: String
    var isAvailable: Bool

    init(id: String, isAvailable: Bool = true) {
        self.id = id
        self.isAvailable = isAvailable
    }

    func start() throws(SpeechCoreError) -> AsyncThrowingStream<TranscriptionSegment, SpeechCoreError> {
        fatalError("Not used in registry tests")
    }

    func stop() async throws(SpeechCoreError) {}
}

@Test func registryReturnsRegisteredService() async {
    let registry = TranscriberRegistry()
    let svc = MockService(id: "apple")
    await registry.register(svc)
    let found = await registry.service(for: "apple")
    #expect(found != nil)
    #expect(found?.id == "apple")
}

@Test func unavailableServiceExcludedFromAvailable() async {
    let registry = TranscriberRegistry()
    let available = MockService(id: "a", isAvailable: true)
    let unavailable = MockService(id: "b", isAvailable: false)
    await registry.register(available)
    await registry.register(unavailable)
    let result = await registry.availableServices()
    #expect(result.count == 1)
    #expect(result[0].id == "a")
}

@Test func duplicateRegistrationOverwrites() async {
    let registry = TranscriberRegistry()
    let first = MockService(id: "x", isAvailable: false)
    let second = MockService(id: "x", isAvailable: true)
    await registry.register(first)
    await registry.register(second)
    let found = await registry.service(for: "x")
    #expect(found != nil)
    let available = await found!.isAvailable
    #expect(available == true)
}

// MARK: - MockFileTranscriber

@Test func mockFileTranscriberYieldsSegments() async throws {
    let segments = try [
        TranscriptionSegment(text: "Hello", startTime: 0.0, endTime: 1.0),
        TranscriptionSegment(text: "World", startTime: 1.0, endTime: 2.0),
    ]
    let mock = MockFileTranscriber(segments: segments)
    let stream = mock.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.wav"), locale: Locale(identifier: "en_US"))
    var collected: [TranscriptionSegment] = []
    for try await segment in stream {
        collected.append(segment)
    }
    #expect(collected == segments)
}

@Test func mockFileTranscriberEmptySegments() async throws {
    let mock = MockFileTranscriber(segments: [])
    let stream = mock.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.wav"), locale: Locale(identifier: "ja_JP"))
    var collected: [TranscriptionSegment] = []
    for try await segment in stream {
        collected.append(segment)
    }
    #expect(collected.isEmpty)
}

@Test func mockFileTranscriberFinishesWithError() async throws {
    struct EngineError: Error, Sendable {}
    let engineError = EngineError()
    let segments = try [
        TranscriptionSegment(text: "Partial", startTime: 0.0, endTime: 1.0),
    ]
    let mock = MockFileTranscriber(segments: segments, error: SpeechCoreError.recognitionFailed(underlying: engineError))
    let stream = mock.transcribe(fileURL: URL(fileURLWithPath: "/tmp/test.wav"), locale: Locale(identifier: "en_US"))
    var collected: [TranscriptionSegment] = []
    do {
        for try await segment in stream {
            collected.append(segment)
        }
        Issue.record("Expected error but stream completed normally")
    } catch {
        guard case SpeechCoreError.recognitionFailed = error else {
            Issue.record("Expected .recognitionFailed but got \(error)")
            return
        }
    }
    #expect(collected == segments)
}

@Test func mockFileTranscriberRejectsNonFileURL() async {
    let mock = MockFileTranscriber(segments: [])
    let stream = mock.transcribe(fileURL: URL(string: "https://example.com/audio.wav")!, locale: Locale(identifier: "en_US"))
    do {
        for try await _ in stream {
            Issue.record("Expected error but received a segment")
        }
        Issue.record("Expected error but stream completed normally")
    } catch {
        if case .invalidInputURL = error as? SpeechCoreError {} else {
            Issue.record("Expected invalidInputURL but got \(error)")
        }
    }
}
