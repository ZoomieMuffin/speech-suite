import Testing
@testable import SpeechCore

// MARK: - TranscriptionSegment

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
    #expect(throws: SpeechCoreError.invalidTimeRange) {
        try TranscriptionSegment(text: "Bad", startTime: 2.0, endTime: 1.0)
    }
}

@Test func segmentInfiniteTimeThrows() {
    #expect(throws: SpeechCoreError.invalidTimeRange) {
        try TranscriptionSegment(text: "Bad", startTime: .infinity, endTime: .infinity)
    }
    #expect(throws: SpeechCoreError.invalidTimeRange) {
        try TranscriptionSegment(text: "Bad", startTime: .nan, endTime: 1.0)
    }
}

@Test func segmentConfidenceOutOfRangeThrows() {
    #expect(throws: SpeechCoreError.self) {
        try TranscriptionSegment(text: "Bad", startTime: 0, endTime: 1, confidence: 1.5)
    }
    #expect(throws: SpeechCoreError.self) {
        try TranscriptionSegment(text: "Bad", startTime: 0, endTime: 1, confidence: -0.1)
    }
}

// MARK: - SpeechCoreError

@Test func errorIsEquatable() {
    #expect(SpeechCoreError.fileNotFound == SpeechCoreError.fileNotFound)
    #expect(SpeechCoreError.unsupportedFormat == SpeechCoreError.unsupportedFormat)
    #expect(SpeechCoreError.invalidTimeRange == SpeechCoreError.invalidTimeRange)
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
