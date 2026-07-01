import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var search = ""
    @State private var confirmClear = false

    private var filtered: [HistoryStore.Entry] {
        guard !search.isEmpty else { return history.entries }
        return history.entries.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filtered) { entry in
                        HistoryRow(entry: entry)
                            .listRowSeparator(.visible)
                    }
                    .onDelete { offsets in
                        offsets.map { filtered[$0] }.forEach(history.delete)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 540)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
            Text("History").font(.headline)
            Text("\(history.entries.count)").foregroundStyle(.secondary).font(.subheadline)
            Spacer()
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
            Button(role: .destructive) { confirmClear = true } label: {
                Label("Clear", systemImage: "trash")
            }
            .disabled(history.entries.isEmpty)
            .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear All", role: .destructive) { history.clear() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.bubble").font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(search.isEmpty ? "No dictations yet" : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let entry: HistoryStore.Entry
    @EnvironmentObject private var history: HistoryStore
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let original = entry.original {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Text("was: \(original)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .strikethrough(color: .secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Text(entry.language.uppercased())
                    .font(.system(size: 9, weight: .bold)).tracking(0.4)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button {
                    copy()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) { history.delete(entry) } label: {
                    Image(systemName: "trash").font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}
