import HelperCore
import SwiftUI

struct ComposerView: View {
    @Environment(AppState.self) private var state
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 8) {
            if state.isTranslating { TranslationPanel() }
            if state.isScrollCapturing { ScrollBanner() }

            if let image = state.attachment {
                HStack(spacing: 10) {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .frame(height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                    Text("Selected area attached. Add a question or just send.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { state.attachment = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            QuickActionsBar()

            HStack(alignment: .bottom, spacing: 8) {
                TextField(placeholder, text: $state.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit { state.send() }
                    .padding(.vertical, 6)

                HStack(spacing: 2) {
                    IconButton(symbol: state.isRecording ? "stop.circle.fill" : "mic", help: "Voice input (⌃⌥V)",
                               tint: state.isRecording ? .red : nil, locked: !state.allowed(.voice)) {
                        Task { await state.toggleRecording() }
                    }
                    IconButton(symbol: "viewfinder", help: "Capture a screen region (⌃⌥S)", locked: !state.allowed(.screenshot)) {
                        Task { await state.captureRegion() }
                    }
                    IconButton(symbol: state.isScrollCapturing ? "checkmark.circle.fill" : "arrow.up.and.down.text.horizontal",
                               help: state.isScrollCapturing ? "Finish scrolled capture and ask" : "Capture a long page while you scroll",
                               tint: state.isScrollCapturing ? .green : nil, locked: !state.allowed(.screenshot)) {
                        Task { await state.toggleScrollCapture() }
                    }
                    IconButton(symbol: "captions.bubble", help: state.isTranslating ? "Stop live translation" : "Live-translate meeting audio",
                               tint: state.isTranslating ? .accentColor : nil, locked: !state.allowed(.translation)) {
                        Task { await state.toggleTranslation() }
                    }
                    if state.isBusy {
                        Button { state.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                            .buttonStyle(.borderless).help("Stop")
                    } else {
                        Button { state.send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                            .buttonStyle(.borderless)
                            .keyboardShortcut(.return, modifiers: .command)
                            .disabled(state.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.attachment == nil)
                            .help("Send (⏎)")
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator))

            HStack {
                Circle().fill(state.isBusy ? .orange : .green).frame(width: 7, height: 7)
                Text(state.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
        .onAppear { focused = true }
    }

    private var placeholder: String {
        state.mode == .practice ? "Type your answer…" : "Ask anything, or paste code…"
    }
}

private struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    var locked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol).font(.system(size: 15))
                    .foregroundStyle(tint ?? .secondary)
                    .frame(width: 26, height: 26)
                if locked {
                    Image(systemName: "lock.fill").font(.system(size: 7)).foregroundStyle(.orange).offset(x: 1, y: 3)
                }
            }
        }
        .buttonStyle(.borderless)
        .help(locked ? "\(help) — Pro" : help)
    }
}

private struct QuickActionsBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QuickAction.allCases) { action in
                    Button { state.send(action) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: action.symbol)
                            Text(action.title)
                            if !state.allowed(action.feature) { Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.orange) }
                        }
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isBusy)
                }
            }
        }
    }
}

private struct TranslationPanel: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 7, height: 7)
                Text("Live translation").font(.caption.weight(.semibold))
                Spacer()
                Button { state.stopTranslation() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            Text(state.subtitles.isEmpty ? "Listening…" : state.subtitles)
                .font(.callout).foregroundStyle(state.subtitles.isEmpty ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(5)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ScrollBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack {
            Image(systemName: "arrow.up.and.down.text.horizontal")
            Text("Scroll through the page, then press ✓ to finish (\(state.scrollFrameCount) captured)")
                .font(.caption)
            Spacer()
        }
        .padding(8)
        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
