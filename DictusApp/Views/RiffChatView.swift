import DictusCore
import RiffLocalRewrite
import SwiftUI

struct RiffChatView: View {
    @ObservedObject var chat: RiffChat

    @AppStorage("riff.chat.model") private var selection = LocalRewriteModel.apple
    @Environment(\.scenePhase) private var scenePhase
    @State private var appleModelName: String?
    @State private var showsModels = false
    @State private var confirmsNewChat = false
    @FocusState private var composing: Bool

    private var model: LocalRewriteModel? {
        LocalRewriteModel.catalog.first { $0.id == selection && $0.isInstalled }
    }

    private var systemModelName: String? {
        selection == LocalRewriteModel.apple ? appleModelName : nil
    }

    private var backend: RiffChatEngine.Backend? {
        if let model { return .downloaded(model) }
        if systemModelName != nil { return .apple }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if chat.messages.isEmpty {
                ContentUnavailableView {
                    Label("Chat on this iPhone", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    if backend == nil {
                        Text("Choose a model to start a conversation.")
                    } else {
                        Text("Type a message to start a conversation.")
                    }
                }
            } else {
                conversation
            }
            if chat.messages.isEmpty, let error = chat.error {
                Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 12)
            }
            composer
        }
        .background(Color.dictusBackground.ignoresSafeArea())
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    composing = false
                    showsModels = true
                } label: {
                    Label {
                        if let name = model?.name ?? systemModelName {
                            Text(name)
                        } else {
                            Text("Choose model")
                        }
                    } icon: {
                        Image(systemName: "cpu")
                    }
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                }
                .disabled(chat.isGenerating)
                .accessibilityIdentifier("chat.model")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("New chat", systemImage: "square.and.pencil") { confirmsNewChat = true }
                    .labelStyle(.iconOnly)
                    .disabled(chat.messages.isEmpty)
                    .accessibilityIdentifier("chat.new")
            }
        }
        .confirmationDialog("Start a new chat?", isPresented: $confirmsNewChat, titleVisibility: .visible) {
            Button("New chat", role: .destructive) { chat.reset() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showsModels, onDismiss: {
            appleModelName = PolishAvailability.appleSystemModelName
        }) {
            NavigationStack {
                OnDeviceModelPicker(
                    selection: $selection,
                    title: "Chat model",
                    caption: "Downloaded models are shared with Smart Modes.",
                    allowsUnavailableApple: false
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsModels = false }
                    }
                }
            }
        }
        .onAppear { appleModelName = PolishAvailability.appleSystemModelName }
        .onDisappear { chat.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appleModelName = PolishAvailability.appleSystemModelName }
            if phase == .background { chat.stop() }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(chat.messages) { message in
                        let isUser = message.role == .user
                        Text(message.text)
                            .textSelection(.enabled)
                            .padding(12)
                            .background(isUser ? Color.dictusAccent.opacity(0.08) : .dictusSurface,
                                        in: RoundedRectangle(cornerRadius: 16))
                            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                            .accessibilityIdentifier(isUser ? "chat.message.user" : "chat.message.assistant")
                    }
                    if chat.isGenerating {
                        ProgressView("Generating reply")
                            .padding(.vertical, 5)
                    } else if let error = chat.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let backend, chat.canRetry {
                        Button("Try again") { chat.retry(using: backend) }
                            .font(.footnote.weight(.semibold))
                    }
                    Color.clear.frame(height: 1).id("chat.end")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat.end", anchor: .bottom) }
            }
            .onChange(of: chat.isGenerating) { _, _ in
                proxy.scrollTo("chat.end", anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message", text: $chat.draft, axis: .vertical)
                .font(.body)
                .lineLimit(1...5)
                .padding(12)
                .background(Color.dictusSurface, in: RoundedRectangle(cornerRadius: 16))
                .focused($composing)
                .disabled(backend == nil)
                .accessibilityIdentifier("chat.compose")

            if chat.isGenerating {
                Button("Stop", systemImage: "stop.circle.fill") { chat.stop() }
                    .accessibilityIdentifier("chat.stop")
            } else {
                Button("Send", systemImage: "arrow.up.circle.fill") {
                    guard let backend else { return }
                    composing = false
                    chat.send(using: backend)
                }
                .disabled(backend == nil || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("chat.send")
            }
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .padding(12)
        .background(.bar)
    }
}

@MainActor
final class RiffChat: ObservableObject {
    @Published var draft = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var error: LocalizedStringKey?
    @Published private(set) var isGenerating = false

    private var generation: Task<Void, Never>?

    var canRetry: Bool { !isGenerating && messages.last?.role == .user }

    func send(using backend: RiffChatEngine.Backend) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        guard text.utf8.count <= 16_384 else {
            error = "This message is too long for the selected model."
            return
        }
        messages.append(ChatMessage(role: .user, text: text))
        draft = ""
        retry(using: backend)
    }

    func retry(using backend: RiffChatEngine.Backend) {
        guard canRetry else { return }
        error = nil
        isGenerating = true
        generation = Task { [weak self, history = messages] in
            do {
                let reply = try await RiffChatEngine.reply(to: history, using: backend)
                try Task.checkCancellation()
                self?.messages.append(ChatMessage(role: .assistant, text: reply.text))
                if reply.reachedLimit { self?.error = "The reply reached its length limit." }
            } catch RiffChatEngine.Failure.messageTooLong {
                if !Task.isCancelled { self?.error = "This message is too long for the selected model." }
            } catch RiffChatEngine.Failure.modelUnavailable {
                if !Task.isCancelled { self?.error = "Choose an available model to continue." }
            } catch {
                if !Task.isCancelled { self?.error = "The model couldn’t reply. Try again." }
            }
            if !Task.isCancelled {
                self?.isGenerating = false
                self?.generation = nil
            }
        }
    }

    func stop() {
        generation?.cancel()
        generation = nil
        isGenerating = false
    }

    func reset() {
        stop()
        messages.removeAll()
        draft = ""
        error = nil
    }
}
