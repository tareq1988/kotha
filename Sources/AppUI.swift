import SwiftUI

/// Standard detail-pane layout: big title + subtitle, then scrolling content.
struct PageScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 26, weight: .bold))
                    if let subtitle {
                        Text(subtitle).font(.body).foregroundStyle(.secondary)
                    }
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.subheadline).fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }
}

/// A titled block of content (header above a card), for use outside Form/List.
struct LabeledSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            content()
        }
    }
}

/// Trailing control for a downloadable model row: progress while busy, a delete
/// button once present, otherwise a Download button. Shared by every model list.
struct DownloadControl: View {
    let isBusy: Bool          // this row's id is the one in flight
    let fraction: Double?     // download progress for this id (nil = indeterminate)
    let isDownloaded: Bool
    let disabled: Bool        // another download is in progress
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if isBusy {
            if let fraction {
                VStack(alignment: .trailing, spacing: 2) {
                    ProgressView(value: fraction).frame(width: 110)
                    Text("\(Int(fraction * 100))%")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                ProgressView().controlSize(.small)
            }
        } else if isDownloaded {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .help("Delete download")
        } else {
            Button("Download", action: onDownload).disabled(disabled)
        }
    }
}

extension View {
    /// Card surface used across Overview cards and grouped rows.
    func cardBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quinary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
