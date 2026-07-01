import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var models: ModelManager
    @EnvironmentObject private var vocabulary: VocabularyStore
    @AppStorage("aiCleanup") private var aiCleanup = true
    @StateObject private var cleanup = CleanupManager.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var tick = 0   // forces permission/device re-read
    @AppStorage("activationMode") private var activationRaw = ActivationMode.hold.rawValue
    @AppStorage("copyToClipboard") private var copyToClipboard = false

    private let poll = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Language → Model") {
                modelPicker("English  (Right ⌘)", language: .english)
                modelPicker("Bangla  (Right ⌥)", language: .bangla)
            }

            Section("Behavior") {
                Picker("Activation", selection: $activationRaw) {
                    ForEach(ActivationMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                if let mode = ActivationMode(rawValue: activationRaw) {
                    Text(mode.help).font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Copy dictated text to clipboard", isOn: $copyToClipboard)
            }

            Section("Local Models") {
                ForEach(ModelCatalog.local) { model in
                    LocalModelRow(model: model)
                }
                HStack {
                    Text("Stored in ~/Library/Application Support/Kotha/Models")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSWorkspace.shared.open(ModelStorage.root)
                    } label: {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    .controlSize(.small)
                }
            }

            Section("Online Models (API keys)") {
                ForEach(ModelCatalog.online) { model in
                    OnlineKeyRow(model: model)
                }
            }

            Section("Vocabulary cleanup") {
                Toggle("Fix known terms with on-device AI", isOn: $aiCleanup)
                Picker("Cleanup model", selection: $cleanup.selectedID) {
                    ForEach(cleanup.catalog) { model in
                        Text("\(model.name) · \(model.size)").tag(model.id)
                    }
                }
                ForEach(cleanup.catalog.filter(\.isLocal)) { model in
                    CleanupModelRow(model: model)
                }
                if cleanup.selectedInfo.provider == .apple, !AICleanup.isAvailable {
                    Label("On-device AI unavailable (needs Apple Intelligence). Casing of known terms is still corrected.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(vocabulary.terms.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        TextField("term", text: $vocabulary.terms[i]).textFieldStyle(.roundedBorder)
                        Button(role: .destructive) { vocabulary.remove(at: i) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { vocabulary.add() } label: {
                    Label("Add term", systemImage: "plus")
                }
                Text("Brand/product names the models mishear. The on-device model replaces mishears of these with the exact term, without changing anything else.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Permissions & Audio") {
                permissionRow("Accessibility", granted: Permissions.accessibilityTrusted) {
                    Permissions.promptAccessibility()
                }
                permissionRow("Microphone", granted: Permissions.microphone == .authorized) {
                    Permissions.requestMicrophone { tick += 1 }
                }
                Picker("Input device", selection: micBinding) {
                    Text("System Default").tag("")
                    ForEach(AudioDevices.inputs()) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LoginItem.set(on) }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .onReceive(poll) { _ in tick += 1 }   // re-render to re-read permission state
    }

    private var micBinding: Binding<String> {
        Binding(
            get: { UserDefaults.standard.string(forKey: AudioDevices.selectionKey) ?? "" },
            set: { UserDefaults.standard.set($0, forKey: AudioDevices.selectionKey) }
        )
    }

    @ViewBuilder
    private func permissionRow(_ title: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            } else {
                Button("Grant") { action() }
            }
        }
    }

    private func modelPicker(_ title: String, language: Language) -> some View {
        let assignedID = models.assignedID(for: language)
        // Only show ready models, but keep the current selection visible so the picker isn't blank.
        var options = ModelCatalog.forLanguage(language).filter { models.ready($0, for: language) }
        if !options.contains(where: { $0.id == assignedID }), let assigned = ModelCatalog.info(assignedID) {
            options.append(assigned)
        }
        let selection = Binding(
            get: { assignedID },
            set: { models.setModel($0, for: language) }
        )
        return Picker(title, selection: selection) {
            ForEach(options) { model in
                Text(model.name + (models.ready(model, for: language) ? "" : "  (setup needed)"))
                    .tag(model.id)
            }
        }
    }
}

// MARK: - Local model row (download / use / delete)

private struct LocalModelRow: View {
    let model: ModelInfo
    @EnvironmentObject private var models: ModelManager

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).fontWeight(.medium)
                Text("\(model.size ?? "") · \(model.detail)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.kind == .appleSpeech {
                if AppleSpeechEngine.authorized {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).labelStyle(.titleAndIcon).font(.caption)
                } else {
                    Button("Grant") {
                        AppleSpeechEngine.requestAuth { models.refresh() }
                    }
                }
            } else if models.busyID == model.id {
                if let fraction = models.progress[model.id] {
                    VStack(alignment: .trailing, spacing: 2) {
                        ProgressView(value: fraction).frame(width: 110)
                        Text("\(Int(fraction * 100))%")
                            .font(.caption2).foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if models.isDownloaded(model.id) {
                Button(role: .destructive) { models.delete(model.id) } label: {
                    Image(systemName: "trash")
                }
                .help("Delete download")
            } else {
                Button("Download") { models.download(model.id) }
                    .disabled(models.busyID != nil)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Cleanup model row (download / delete for MLX models)

private struct CleanupModelRow: View {
    let model: CleanupModelInfo
    @ObservedObject private var cleanup = CleanupManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.name).font(.callout).fontWeight(.medium)
                Text("\(model.size) · \(model.detail)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if cleanup.busyID == model.id {
                if let fraction = cleanup.progress[model.id] {
                    VStack(alignment: .trailing, spacing: 2) {
                        ProgressView(value: fraction).frame(width: 100)
                        Text("\(Int(fraction * 100))%").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if cleanup.isDownloaded(model.id) {
                Button(role: .destructive) { cleanup.delete(model.id) } label: {
                    Image(systemName: "trash")
                }
                .help("Delete download")
            } else {
                Button("Download") { cleanup.download(model.id) }
                    .disabled(cleanup.busyID != nil)
            }
        }
        .padding(.leading, 8)
    }
}

// MARK: - Online key row

private struct OnlineKeyRow: View {
    let model: ModelInfo
    @EnvironmentObject private var models: ModelManager
    @State private var key = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.name).fontWeight(.medium)
                if models.hasKey(model) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
            }
            HStack {
                SecureField("API key", text: $key)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    models.saveKey(key, for: model)
                    saved = true
                }
                if saved { Text("Saved").font(.caption).foregroundStyle(.green) }
            }
        }
        .padding(.vertical, 2)
        .onAppear { key = models.key(for: model) }
        .onChange(of: key) { _, _ in saved = false }
    }
}
