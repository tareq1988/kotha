import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case overview, history, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .history:  return "History"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "chart.bar.xaxis"
        case .history:  return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var models: ModelManager
    @EnvironmentObject private var vocabulary: VocabularyStore
    @EnvironmentObject private var history: HistoryStore
    @AppStorage("mainSection") private var sectionRaw = AppSection.overview.rawValue

    private var selection: Binding<AppSection?> {
        Binding(
            get: { AppSection(rawValue: sectionRaw) ?? .overview },
            set: { if let value = $0 { sectionRaw = value.rawValue } }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 220, max: 260)
        } detail: {
            detail
                .frame(minWidth: 520, minHeight: 560)
        }
        .navigationTitle("Kotha")
        .background(WindowAccessor())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Kotha").font(.title3).fontWeight(.semibold)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            List(AppSection.allCases, selection: selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.icon)
                }
            }
            .listStyle(.sidebar)

            Divider()
            statusFooter
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(app.isBusy ? Color.orange : Color.green)
                .frame(width: 7, height: 7)
            Text(app.statusText)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detail: some View {
        switch AppSection(rawValue: sectionRaw) ?? .overview {
        case .overview: OverviewView()
        case .history:  HistoryView()
        case .settings: SettingsView()
        }
    }
}
