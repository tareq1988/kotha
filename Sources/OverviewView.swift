import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var models: ModelManager
    @State private var rateTick = 0   // recompute costs when a rate is edited

    private var stats: HistoryStore.Stats { history.stats }

    private struct Usage { let model: ModelInfo; let seconds: Double; let cost: Double }

    private var onlineUsage: [Usage] {
        _ = rateTick
        return ModelCatalog.online.compactMap { model in
            let seconds = stats.secondsByModel[model.id] ?? 0
            guard seconds > 0 else { return nil }
            return Usage(model: model, seconds: seconds,
                         cost: CostRates.cost(seconds: seconds, modelID: model.id))
        }
    }
    private var totalSpent: Double { onlineUsage.reduce(0) { $0 + $1.cost } }

    static func usd(_ value: Double) -> String { String(format: "$%.4f", value) }

    var body: some View {
        PageScaffold(title: "Overview",
                     subtitle: "Your dictation activity at a glance.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                StatCard(icon: "text.word.spacing", tint: .blue,
                         value: stats.words.formatted(), label: "Words dictated")
                StatCard(icon: "waveform", tint: .purple,
                         value: stats.dictations.formatted(), label: "Dictations")
                StatCard(icon: "clock.badge.checkmark", tint: .green,
                         value: timeSaved, label: "Time saved vs. typing")
                StatCard(icon: "chart.bar.fill", tint: .orange,
                         value: stats.averageWords.formatted(), label: "Avg words / dictation")
                StatCard(icon: "textformat.characters", tint: .teal,
                         value: stats.characters.formatted(), label: "Characters")
                StatCard(icon: "calendar", tint: .pink,
                         value: sinceText, label: "Dictating since")
                if !onlineUsage.isEmpty {
                    StatCard(icon: "dollarsign.circle.fill", tint: .green,
                             value: OverviewView.usd(totalSpent), label: "Spent on online models")
                }
            }

            if !languageRows.isEmpty {
                LabeledSection(title: "By language") {
                    VStack(spacing: 0) {
                        ForEach(languageRows, id: \.lang) { row in
                            LanguageRow(lang: row.lang, words: row.words, fraction: row.fraction)
                            if row.lang != languageRows.last?.lang { Divider() }
                        }
                    }
                    .cardBackground()
                }
            }

            if !onlineUsage.isEmpty {
                LabeledSection(title: "Online usage & cost") {
                    VStack(spacing: 0) {
                        ForEach(onlineUsage, id: \.model.id) { usage in
                            CostRow(model: usage.model, seconds: usage.seconds) { rateTick += 1 }
                            if usage.model.id != onlineUsage.last?.model.id { Divider() }
                        }
                        Divider()
                        HStack {
                            Text("Total").fontWeight(.semibold)
                            Spacer()
                            Text(OverviewView.usd(totalSpent))
                                .fontWeight(.semibold).monospacedDigit()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                    }
                    .cardBackground()
                    Text("Cost is estimated from audio duration × your per-minute rate. Edit the rate to match your provider's current pricing. Tracked from when this feature was added.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.leading, 2).padding(.top, 2)
                }
            }

            LabeledSection(title: "Active models") {
                VStack(spacing: 0) {
                    modelRow("Right ⌘  ·  English", name: models.name(for: .english))
                    Divider()
                    modelRow("Right ⌥  ·  Bangla", name: models.name(for: .bangla))
                }
                .cardBackground()
            }

            if stats.dictations > 0 {
                Button(role: .destructive) { history.resetStats() } label: {
                    Label("Reset statistics", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    private var timeSaved: String {
        let seconds = stats.timeSavedSeconds
        if seconds < 60 { return "\(Int(seconds))s" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60, rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }

    private var sinceText: String {
        guard let date = stats.firstUse else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private struct LangRow { let lang: String; let words: Int; let fraction: Double }

    private var languageRows: [LangRow] {
        let total = max(1, stats.wordsByLanguage.values.reduce(0, +))
        return stats.wordsByLanguage
            .sorted { $0.value > $1.value }
            .map { LangRow(lang: $0.key, words: $0.value, fraction: Double($0.value) / Double(total)) }
    }

    private func modelRow(_ title: String, name: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(name).fontWeight(.medium)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

// MARK: - Pieces

private struct StatCard: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardBackground()
    }
}

private struct CostRow: View {
    let model: ModelInfo
    let seconds: Double
    var onRateChange: () -> Void
    @State private var rate: Double

    init(model: ModelInfo, seconds: Double, onRateChange: @escaping () -> Void) {
        self.model = model
        self.seconds = seconds
        self.onRateChange = onRateChange
        _rate = State(initialValue: CostRates.rate(for: model.id))
    }

    private var minutes: Double { seconds / 60.0 }
    private var cost: Double { minutes * rate }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).fontWeight(.medium)
                Text(String(format: "%.1f min of audio · ≈ $%.2f/hr", minutes, rate * 60))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 3) {
                Text("$").foregroundStyle(.secondary)
                TextField("", value: $rate, format: .number.precision(.fractionLength(2...4)))
                    .frame(width: 60).multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: rate) { _, value in
                        CostRates.setRate(value, for: model.id)
                        onRateChange()
                    }
                Text("/min").font(.caption).foregroundStyle(.secondary)
            }
            Text(OverviewView.usd(cost))
                .fontWeight(.semibold).monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

private struct LanguageRow: View {
    let lang: String
    let words: Int
    let fraction: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(lang.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(0.4)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            ProgressView(value: fraction)
                .frame(maxWidth: .infinity)
            Text("\(words)")
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}
