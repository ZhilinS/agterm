import ArgumentParser
import Foundation
import Testing
import agtermCore
@testable import agtermctlKit

// Fork: page sharing's CLI coverage, kept out of upstream's test files.
struct PageShareCommandsTests {
    private func request(_ argv: [String]) throws -> ControlRequest {
        let parsed = try Agtermctl.parseAsRoot(argv)
        guard let command = parsed as? any RequestCommand else {
            throw SocketClientError("parsed \(argv) is not a RequestCommand")
        }
        return try command.makeRequest()
    }

    private func rejects(_ argv: [String]) -> Bool {
        (try? Agtermctl.parseAsRoot(argv)) == nil
    }

    @Test func shareSendsThePane() throws {
        let req = try request(["session", "overlay", "share", "--pane", "right", "--target", "s"])
        #expect(req.cmd == .sessionOverlayShare)
        #expect(req.target == "s")
        #expect(req.args?.pane == "right")
        #expect(try request(["session", "overlay", "share"]).args == nil)
        #expect(rejects(["session", "overlay", "share", "--pane", "middle"]))
    }

    @Test func commentsSendThePane() throws {
        let req = try request(["session", "overlay", "comments", "--pane", "left", "--target", "s"])
        #expect(req.cmd == .sessionOverlayComments)
        #expect(req.target == "s")
        #expect(req.args?.pane == "left")
        #expect(try request(["session", "overlay", "comments"]).args == nil)
        #expect(rejects(["session", "overlay", "comments", "--pane", "middle"]))
    }

    @Test func formatResponsePrintsDiscussionsAsJSON() throws {
        let discussion = ControlPageDiscussion(id: "d1", notes: [
            ControlPageNote(id: 1, author: "Ann", body: "a/b", createdAt: "2026-10-21T10:00:00Z", system: false),
        ])
        var result = ControlResult()
        result.discussions = [discussion]
        var empty = ControlResult()
        empty.discussions = []

        #expect(SocketClient.formatResponse(ControlResponse(ok: true, result: result))
            == #"[{"id":"d1","notes":[{"author":"Ann","body":"a/b","createdAt":"2026-10-21T10:00:00Z","id":1,"system":false}]}]"#)
        #expect(SocketClient.formatResponse(ControlResponse(ok: true, result: empty)) == "[]")
    }
}
