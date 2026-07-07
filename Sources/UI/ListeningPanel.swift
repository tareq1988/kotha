import AppKit
import SwiftUI
import Combine

/// Floating dictation HUD. Driven by AppState.status: it appears while recording,
/// stays through transcription, and shows a success / error flash before dismissing.
@MainActor
final class ListeningPanel {
    static let shared = ListeningPanel()

    private var panel: NSPanel?
    private var visible = false
    private var cancellable: AnyCancellable?

    func start() {
        cancellable = AppState.shared.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.update(for: status) }
    }

    private func update(for status: AppState.Status) {
        switch status {
        case .idle, .loadingModel:
            hide()
        default:
            showIfNeeded()
        }
    }

    private func showIfNeeded() {
        if panel == nil { makePanel() }
        guard let panel, !visible else { return }
        visible = true
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard let panel, visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.visible == false { panel.orderOut(nil) }
            }
        })
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.minY + 96))
    }

    private func makePanel() {
        let size = NSSize(width: 280, height: 68)
        let hosting = NSHostingView(rootView: HUDView().environmentObject(AppState.shared))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false   // allow hover to reveal the cancel button
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hosting
        self.panel = panel
    }
}

// MARK: - HUD view

private struct HUDView: View {
    @EnvironmentObject private var app: AppState
    @State private var hovering = false

    private enum Phase: Equatable {
        case recording(Language), transcribing(Language), refining(Language)
        case success(Language), error(String), hidden
    }

    private var phase: Phase {
        switch app.status {
        case .recording(let l):    return .recording(l)
        case .transcribing(let l): return .transcribing(l)
        case .refining(let l):     return .refining(l)
        case .success(let l):      return .success(l)
        case .error(let m):        return .error(m)
        default:                   return .hidden
        }
    }

    private var cancellable: Bool {
        switch phase {
        case .recording, .transcribing, .refining: return true
        default:                                    return false
        }
    }

    var body: some View {
        HStack(spacing: 13) {
            badge
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(width: 280, height: 68)
        .background(.regularMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if hovering && cancellable {
                Button { app.cancelCurrent() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.35))
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .padding(7)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: app.status)
        .animation(.easeInOut(duration: 0.12), value: hovering)
    }

    // Leading badge — flat, monochrome, symbol-based

    @ViewBuilder private var badge: some View {
        // While a session is active, show the target app's icon (like the app it inserts into);
        // otherwise fall back to a monochrome phase symbol.
        if showsAppContext, let icon = app.focusedApp?.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
    }

    /// Phases where the HUD represents an active insertion target.
    private var showsAppContext: Bool {
        switch phase {
        case .recording, .transcribing, .refining: return true
        default:                                    return false
        }
    }

    /// The target app's name, when known, else a phase-appropriate fallback.
    private func title(_ fallback: String) -> String {
        (showsAppContext ? app.focusedApp?.name : nil) ?? fallback
    }

    private var symbol: String {
        switch phase {
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        case .refining:     return "sparkles"
        case .success:      return "checkmark"
        case .error:        return "exclamationmark.triangle.fill"
        case .hidden:       return "mic"
        }
    }

    // Main content

    @ViewBuilder private var content: some View {
        switch phase {
        case .recording(let l):
            VStack(alignment: .leading, spacing: 5) {
                titleRow(title("Listening"), l)
                Waveform(level: CGFloat(app.micLevel), tint: accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .transcribing(let l):
            VStack(alignment: .leading, spacing: 6) {
                titleRow(title("Transcribing"), l)
                BouncingDots(tint: accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .refining(let l):
            VStack(alignment: .leading, spacing: 6) {
                titleRow(title("Refining"), l)
                BouncingDots(tint: accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .success:
            VStack(alignment: .leading, spacing: 2) {
                Text("Inserted").font(.system(size: 14, weight: .semibold))
                Text("Text sent to the app").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .error(let message):
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn’t transcribe").font(.system(size: 14, weight: .semibold))
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        case .hidden:
            EmptyView()
        }
    }

    private func titleRow(_ title: String, _ lang: Language) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
            Text(lang.display)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(accent.opacity(0.16), in: Capsule())
                .foregroundStyle(accent)
            Spacer(minLength: 10)
            if !hovering { brand }      // hover swaps the brand for the cancel button
        }
    }

    // Trailing brand mark, echoing the target app on the left.
    private var brand: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform").font(.system(size: 11, weight: .semibold))
            Text("Kotha").font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .transition(.opacity)
    }

    // Theming

    private var accent: Color {
        switch phase {
        case .recording(let l), .transcribing(let l), .refining(let l), .success(let l):
            return l == .bangla ? Color(red: 0.16, green: 0.62, blue: 0.40)   // muted emerald
                                : Color(red: 0.20, green: 0.45, blue: 0.92)   // muted blue
        case .error:    return Color(red: 0.85, green: 0.32, blue: 0.30)
        case .hidden:   return .gray
        }
    }
}

// MARK: - Animated bits

private struct Waveform: View {
    let level: CGFloat
    let tint: Color

    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            // Fill the full available width with as many bars as fit.
            let count = max(1, Int((geo.size.width + spacing) / (barWidth + spacing)))
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        let phase = Double(i) * 0.55
                        let wave = (sin(t * 7 + phase) + 1) / 2      // 0...1
                        let amp = max(0.10, Double(level))
                        let height = 4 + CGFloat(wave * amp) * 22
                        Capsule().fill(tint.opacity(0.9))
                            .frame(width: barWidth, height: height)
                    }
                }
                .frame(width: geo.size.width, height: 26, alignment: .leading)
            }
        }
        .frame(height: 26)
    }
}

private struct BouncingDots: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let o = (sin(t * 4 + Double(i) * 0.7) + 1) / 2
                    Circle().fill(tint)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * o)
                        .scaleEffect(0.8 + 0.4 * o)
                }
            }
            .frame(height: 18, alignment: .center)
        }
    }
}
