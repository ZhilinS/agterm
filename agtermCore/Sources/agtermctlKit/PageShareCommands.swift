import ArgumentParser
import Foundation
import agtermCore

// Fork: page sharing's CLI, kept out of upstream's command files.
extension Session.Overlay {
    struct Share: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Publish a file overlay to GitLab Pages and print its link; the pipeline deploys it after the reply.",
            discussion: "Settings > Sharing names the GitLab project. The same file always gets the same link.")
        @Option(name: .long, help: "Share that split pane's page (primary/left/top or split/right/bottom); omit for the session-wide overlay.")
        var pane: String?
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func validate() throws { try Session.Overlay.validatePane(pane) }

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .sessionOverlayShare, target: target.target,
                           args: options.withWindow(pane.map { ControlArgs(pane: $0) }))
        }
    }

    struct Comments: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Print a shared file overlay's GitLab comments as JSON.",
            discussion: "Needs the OAuth Application ID in Settings > Sharing. Note bodies are raw; empty before the first comment.")
        @Option(name: .long, help: "Read that split pane's page (primary/left/top or split/right/bottom); omit for the session-wide overlay.")
        var pane: String?
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func validate() throws { try Session.Overlay.validatePane(pane) }

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .sessionOverlayComments, target: target.target,
                           args: options.withWindow(pane.map { ControlArgs(pane: $0) }))
        }
    }
}

extension SocketClient {
    /// The page script's own feed, so it stays JSON even without `--json`.
    static func formatDiscussions(_ discussions: [ControlPageDiscussion]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(discussions)) ?? Data("[]".utf8), as: UTF8.self)
    }
}
