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
