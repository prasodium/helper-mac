import HelperCore
import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if state.messages.isEmpty {
                    EmptyState()
                        .padding(.top, 50)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(state.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(16)
                }
            }
            .scrollIndicators(.automatic)
            .onChange(of: state.messages.last?.text) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: state.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

private struct EmptyState: View {
    @Environment(AppState.self) private var state
    
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: emptyIcon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tint)
            
            Text(emptyTitle)
                .font(.title2.weight(.semibold))
            
            Text("Ask a question, paste code, or capture part of your screen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Hotkeys.Action.allCases, id: \.self) { action in
                    HStack {
                        Text(action.display)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                        Text(action.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
            
            if !state.hasAPIKey {
                SettingsLink {
                    Label("Add your OpenAI API key", systemImage: "key")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }
    
    private var emptyIcon: String {
        switch state.mode {
        case .chat: "sparkles"
        case .test: "checklist"
        case .interview: "bubble.left.and.text.bubble.right"
        }
    }
    
    private var emptyTitle: String {
        switch state.mode {
        case .chat: "How can I help?"
        case .test: "Test mode"
        case .interview: "Interview mode"
        }
    }
}

struct MessageRow: View {
    @Environment(AppState.self) private var state
    let message: ChatEntry
    @Local private var hovering = false

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let data = message.thumbnail, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 40)
            
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if message.text.isEmpty {
                    ProgressView().controlSize(.small)
                } else if message.isError {
                    Label(message.text, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .textSelection(.enabled)
                } else {
                    MarkdownView(text: message.text)
                }
                
                if hovering, !message.text.isEmpty, !message.isError {
                    HStack(spacing: 12) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                }
            }
            .onHover { hovering = $0 }
        }
    }
}