import Testing
@testable import SpeechCore

// MARK: - TranscriptionSegment

@Test func segmentStoresFields() {
    let seg = TranscriptionSegment(
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

@Test func segmentConfidenceIsOptional() {
    let seg = TranscriptionSegment(text: "Hi", startTime: 0, endTime: 1)
    #expect(seg.confidence == nil)
}

@Test func segmentZeroDurationIsValid() {
    let seg = TranscriptionSegment(text: "", startTime: 1.0, endTime: 1.0)
    #expect(seg.duration == 0)
}

// MARK: - SpeechCoreError

@Test func errorIsEquatable() {
    #expect(SpeechCoreError.fileNotFound == SpeechCoreError.fileNotFound)
    #expect(SpeechCoreError.unsupportedFormat == SpeechCoreError.unsupportedFormat)
}

// MARK: - HallucinationFilter

@Test func filterRemovesShortSegments() {
    let segments = [
        TranscriptionSegment(text: "Hi", startTime: 0.0, endTime: 0.2),   // 0.2s → removed
        TranscriptionSegment(text: "Hello world", startTime: 1.0, endTime: 2.0), // 1.0s → kept
        TranscriptionSegment(text: "Ok", startTime: 3.0, endTime: 3.4),   // 0.4s → removed
        TranscriptionSegment(text: "Good morning", startTime: 4.0, endTime: 5.5), // 1.5s → kept
    ]
    let filter = HallucinationFilter(minimumDuration: 0.5)
    let result = filter.filter(segments)
    #expect(result.count == 2)
    #expect(result[0].text == "Hello world")
    #expect(result[1].text == "Good morning")
}

@Test func filterKeepsAllWhenNoneShort() {
    let segments = [
        TranscriptionSegment(text: "Hello", startTime: 0.0, endTime: 1.0),
        TranscriptionSegment(text: "World", startTime: 1.0, endTime: 2.0),
    ]
    let filter = HallucinationFilter(minimumDuration: 0.5)
    let result = filter.filter(segments)
    #expect(result.count == 2)
}

@Test func filterWithDefaultThreshold() {
    let short = TranscriptionSegment(text: "Hi", startTime: 0.0, endTime: 0.4)
    let normal = TranscriptionSegment(text: "Hello", startTime: 1.0, endTime: 2.0)
    let filter = HallucinationFilter()
    let result = filter.filter([short, normal])
    #expect(result.count == 1)
    #expect(result[0].text == "Hello")
}
