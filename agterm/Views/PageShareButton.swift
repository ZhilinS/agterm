import SwiftUI
import agtermCore

// Fork: the page strip's Share button, kept out of upstream's HtmlOverlayView.
/// publishing: a click opens the pipeline; idle or failed: a click shares, which retries a failure.
struct PageShareButton: View {
    let overlay: HtmlOverlay
    let tint: Color

    var body: some View {
        if case .file(let path, _) = overlay.source, PageSharing.shared.config != nil {
            button(path)
        }
    }

    private func button(_ path: String) -> some View {
        let share = PageShares.shared.share(forFile: path)
        return Button {
            if share?.state == .publishing {
                if let pipeline = share?.pipelineURL.flatMap(URL.init(string:)) {
                    _ = HtmlOverlayRegistry.shared.browser.open(pipeline)
                }
            } else {
                Task { await PageSharing.shared.share(file: path, copyLink: true) }
            }
        } label: {
            switch share?.state {
            case .publishing:
                ProgressView()
                    .controlSize(.mini)
            case .failed:
                Image(systemName: "exclamationmark.triangle")
            default:
                Image(systemName: "square.and.arrow.up")
            }
        }
        .buttonStyle(HtmlToolbarButtonStyle(tint: tint))
        .opacity(share?.state == .publishing ? 0.5 : 1)
        .help(help(share))
        .accessibilityLabel("Share")
        .accessibilityIdentifier("htmlOverlay.share")
    }

    private func help(_ share: PageShare?) -> String {
        switch share?.state {
        case .publishing: "Deploying to GitLab — click to open the pipeline"
        case .failed: "Share failed: \(share?.error ?? "unknown error") — click to retry"
        default: "Share to GitLab Pages: copies the link"
        }
    }
}
