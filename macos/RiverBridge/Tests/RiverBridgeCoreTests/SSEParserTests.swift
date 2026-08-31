// SSE parser: pure state machine, fed line by line — including the empty
// line that delimits messages (the reason SSEClient splits bytes manually).

import Testing
@testable import RiverBridgeCore

@Test func parsesEventAndData() {
    var parser = SSEParser()
    #expect(parser.feed(line: "event: state") == nil)
    #expect(parser.feed(line: "data: {\"a\": 1}") == nil)
    let message = parser.feed(line: "")
    #expect(message == SSEMessage(event: "state", data: "{\"a\": 1}"))
}

@Test func multipleMessagesAndDefaults() {
    var parser = SSEParser()
    _ = parser.feed(line: "data: primeiro")
    let first = parser.feed(line: "")
    #expect(first == SSEMessage(event: "message", data: "primeiro"))

    _ = parser.feed(line: "event: event")
    _ = parser.feed(line: "data: segundo")
    let second = parser.feed(line: "")
    #expect(second == SSEMessage(event: "event", data: "segundo"))
}

@Test func heartbeatAndBlankWithoutDataYieldNothing() {
    var parser = SSEParser()
    #expect(parser.feed(line: ": ping") == nil)
    #expect(parser.feed(line: "") == nil)
}

@Test func multilineDataJoined() {
    var parser = SSEParser()
    _ = parser.feed(line: "data: linha1")
    _ = parser.feed(line: "data: linha2")
    let message = parser.feed(line: "")
    #expect(message?.data == "linha1\nlinha2")
}
