import SwiftUI
import UIKit
import os.log

private let chatLog = Logger(subsystem: "ai.ecoinference.app", category: "ChatView")

// MARK: - Message model

private struct Message: Identifiable {
    let id         = UUID()
    let role       : Role
    var text       : String
    var image      : UIImage? = nil   // user messages: attached thumbnail for display
    var chartImage : UIImage? = nil   // assistant messages: tool-generated chart

    enum Role {
        case user
        case assistant
        case error
        /// Generated Python code block (from `use tool` command).
        case code
        /// Agentic tool call in progress / completed.
        case tool(name: String)
    }
}

// MARK: - ChatView

struct ChatView: View {

    @EnvironmentObject private var appState: AppState

    // ── Display state ─────────────────────────────────────────────────────────
    @State private var messages:   [Message] = []
    @State private var isGenerating = false
    @State private var streamingId: UUID?
    @State private var inferTask:   Task<Void,Never>? = nil
    @State private var scrollProxy: ScrollViewProxy? = nil

    // ── Full conversation history for inference engine ─────────────────────
    // Tracks every turn including intermediate tool-call exchanges so the
    // engine's KV-cache committedMessageCount stays in sync.
    @State private var inferenceHistory: [InferenceMessage] = []

    // ── Image attachment state ────────────────────────────────────────────────
    @State private var pendingImage: UIImage?   = nil
    @State private var showSourceSheet          = false
    @State private var showImagePicker          = false
    @State private var pickerSource: UIImagePickerController.SourceType = .photoLibrary

    // ── Text input ────────────────────────────────────────────────────────────
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    private var modelReady:   Bool { appState.modelLoaded && !appState.isLoading }
    private var isMultimodal: Bool { InferenceService.shared.isMultimodal }

    // ── Regex: `use tool <request>` ───────────────────────────────────────────
    private static let toolCmdRe = try! NSRegularExpression(
        pattern: #"^use tool\s+(.+)$"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {

            // ── Compact title bar ─────────────────────────────────────────────
            Text("Chat")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.background)
                .overlay(alignment: .bottom) { Divider() }

            // ── No-model banner ───────────────────────────────────────────────
            if !appState.modelLoaded {
                noModelBanner
            }

            // ── Message list ──────────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            MessageBubble(
                                message:     msg,
                                isStreaming: msg.id == streamingId
                            )
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear { scrollProxy = proxy }
                .onChange(of: inputFocused) { _, focused in
                    if focused { scrollToBottom() }
                }
            }
        }
        // ── Input bar pinned above keyboard ───────────────────────────────────
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                inputBar
            }
            .background(.background)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        } // NavigationStack
        // ── Image source picker ───────────────────────────────────────────────
        .confirmationDialog("Attach Image", isPresented: $showSourceSheet) {
            Button("Photo Library") { pickerSource = .photoLibrary; showImagePicker = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera")   { pickerSource = .camera;        showImagePicker = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: pickerSource) { picked in
                pendingImage    = resized(picked, maxDimension: 1024)
                showImagePicker = false
            } onCancel: { showImagePicker = false }
        }
        // ── Deep link handler ─────────────────────────────────────────────────
        .onChange(of: appState.deepLink) { _, action in
            guard let action else { return }
            switch action {
            case .openChat(let prefill, let autoSend, let system):
                if let prefill { inputText = prefill }
                if autoSend, let prefill, !prefill.isEmpty {
                    send(text: prefill, systemOverride: system)
                }
            case .backgroundInfer(let prompt, let callback):
                runBackgroundInfer(prompt: prompt, callbackURL: callback)
            default:
                break
            }
        }
    }

    // MARK: - Sub-views

    private var noModelBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("No model loaded — go to **Models** to load one.").font(.footnote)
            Spacer()
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var inputBar: some View {
        VStack(spacing: 4) {
            // ── Clear / Stop controls ─────────────────────────────────────────
            if !messages.isEmpty || isGenerating {
                HStack {
                    if !messages.isEmpty {
                        Button("Clear") {
                            messages = []
                            pendingImage = nil
                            inferenceHistory = []
                            InferenceService.shared.resetConversation()
                            dlog("Clear — messages + inferenceHistory reset")
                        }
                        .font(.footnote).disabled(isGenerating)
                    }
                    Spacer()
                    if isGenerating {
                        Button("Stop") { stopGeneration() }
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal).padding(.top, 4)
            }

            // ── Pending image thumbnail ───────────────────────────────────────
            if let img = pendingImage {
                HStack {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button { pendingImage = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.black.opacity(0.6))
                        }
                        .offset(x: 6, y: -6)
                    }
                    Spacer()
                }
                .padding(.horizontal).padding(.top, 4)
            }

            // ── Text field row ────────────────────────────────────────────────
            HStack(alignment: .bottom, spacing: 2) {
                if modelReady && appState.imageInputEnabled {
                    Button { showSourceSheet = true } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 22))
                            .foregroundStyle(isGenerating ? Color.gray : Color.secondary)
                    }
                    .disabled(isGenerating)
                    .padding(.leading, 10).padding(.bottom, 7)
                }

                TextField(pendingImage != nil ? "Add a caption…" : "Message",
                          text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...6)
                    .disabled(isGenerating)
                    .focused($inputFocused)
                    .onSubmit { sendCurrentInput() }
                    .padding(.leading, (modelReady && isMultimodal) ? 4 : 12)

                Button(action: sendCurrentInput) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? .blue : .gray)
                }
                .disabled(!canSend)
                .padding(.trailing, 12)
            }
            .padding(.vertical, 10)
        }
    }

    private var canSend: Bool {
        modelReady && !isGenerating &&
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil)
    }

    // MARK: - Send current input

    private func sendCurrentInput() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImage != nil else { return }

        // ── Command shortcuts (text-only) ─────────────────────────────────────
        if pendingImage == nil {
            if text.lowercased() == "list tools" {
                handleListTools(rawInput: text)
                return
            }
            let nsText  = text as NSString
            let range   = NSRange(location: 0, length: nsText.length)
            if let m    = Self.toolCmdRe.firstMatch(in: text, range: range) {
                let reqRange = m.range(at: 1)
                let request  = nsText.substring(with: reqRange).trimmingCharacters(in: .whitespaces)
                handleToolCommand(rawInput: text, request: request)
                return
            }
        }

        // ── Normal chat send ──────────────────────────────────────────────────
        let image    = pendingImage
        inputText    = ""
        pendingImage = nil
        inputFocused = false
        send(text: text, image: image)
    }

    // MARK: - list tools handler

    private func handleListTools(rawInput: String) {
        messages.append(Message(role: .user,      text: rawInput))
        messages.append(Message(role: .assistant, text: PythonCommand.listMessage()))
        scrollToBottom()
    }

    // MARK: - use tool <request> handler

    private func handleToolCommand(rawInput: String, request: String) {
        guard modelReady else { return }

        // Show user bubble + generating placeholder
        messages.append(Message(role: .user, text: rawInput))
        let codePlaceholder = Message(role: .code, text: "Generating Python code…")
        messages.append(codePlaceholder)
        let targetId = codePlaceholder.id
        streamingId  = targetId
        isGenerating = true
        scrollToBottom()

        // Fetch location in parallel then build prompt
        let inference = InferenceService.shared
        inferTask = Task.detached(priority: .userInitiated) {
            dlog("handleToolCommand: Task started — request='\(request)'")

            // Optional GPS preamble
            dlog("handleToolCommand: calling LocationService.requestLocation()")
            let locPreamble: String? = try? await LocationService.shared.requestLocation().pythonPreamble
            dlog("handleToolCommand: requestLocation returned — locPreamble=\(locPreamble == nil ? "nil" : "present")")

            let prompt = PythonCommand.buildToolPrompt(request: request,
                                                       locationPreamble: locPreamble)
            dlog("handleToolCommand: prompt built — \(prompt.count) chars")
            do {
                // Isolate this single-shot call from any prior conversation KV-cache state.
                dlog("handleToolCommand: calling resetConversation()")
                inference.resetConversation()
                dlog("handleToolCommand: calling inference.chat()")
                let raw  = try inference.chat(
                    messages:    [InferenceMessage(role: "user", text: prompt)],
                    maxTokens:   1024,
                    temperature: 0.1
                )
                dlog("handleToolCommand: chat() returned — raw=\(raw.count) chars")
                // Reset again so the tool call doesn't contaminate the next chat turn.
                inference.resetConversation()
                let code = PythonCommand.extractCode(from: raw) ?? raw
                guard !Task.isCancelled else { dlog("handleToolCommand: cancelled after chat"); return }
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == targetId }) {
                        messages[idx].text = code
                    }
                    // Clear inferenceHistory so the next regular chat starts fresh.
                    // resetConversation() wiped the engine's KV-cache; stale history here
                    // would cause the next send() to replay the wrong message index.
                    inferenceHistory = []
                    scrollToBottom()
                }
                dlog("handleToolCommand: UI updated with code (\(code.count) chars)")
            } catch {
                dlog("handleToolCommand: chat() threw — \(error.localizedDescription)")
                inference.resetConversation()
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == targetId }) {
                        messages[idx] = Message(role: .error,
                                                text: "⚠️ Code generation failed: \(error.localizedDescription)")
                    }
                }
            }
            dlog("handleToolCommand: Task finishing — clearing isGenerating")
            await MainActor.run { isGenerating = false; streamingId = nil; inferTask = nil }
        }
    }

    // MARK: - Normal chat send

    private func send(text: String, image: UIImage? = nil, systemOverride: String? = nil) {
        guard modelReady else { return }

        let turnIndex = messages.filter {
            if case .user = $0.role { return true }; return false
        }.count + 1
        chatLog.info("▶︎ send() turn=\(turnIndex) chars=\(text.count) hasImage=\(image != nil)")
        dlog("send() turn=\(turnIndex) text=\(text.prefix(60)) hasImage=\(image != nil)")

        // ── User bubble ───────────────────────────────────────────────────────
        messages.append(Message(role: .user, text: text, image: image))

        // ── Assistant placeholder ─────────────────────────────────────────────
        let assistantMsg = Message(role: .assistant, text: "")
        messages.append(assistantMsg)
        streamingId  = assistantMsg.id
        isGenerating = true
        scrollToBottom()

        // ── Build inferenceHistory for this turn ──────────────────────────────
        if inferenceHistory.isEmpty {
            // First turn of the conversation: inject system prompt + tool block
            var systemParts: [String] = []
            if let sys = systemOverride ?? SettingsService.shared.systemPrompt, !sys.isEmpty {
                systemParts.append(sys)
            }
            let toolBlock = ToolRegistry.shared.buildSystemPromptBlock()
            if !toolBlock.isEmpty { systemParts.append(toolBlock) }
            if !systemParts.isEmpty {
                inferenceHistory.append(InferenceMessage(role: "system",
                                                         text: systemParts.joined(separator: "\n\n")))
            }
        }

        let imageData = image?.jpegData(compressionQuality: 0.85)
        let sendText  = text.isEmpty ? " " : text
        inferenceHistory.append(InferenceMessage(role: "user", text: sendText, imageData: imageData))

        let historySnapshot = inferenceHistory
        let inference       = InferenceService.shared
        let targetId        = assistantMsg.id

        inferTask = Task.detached(priority: .userInitiated) {
            var taskHistory     = historySnapshot
            var pendingChart: UIImage? = nil

            chatLog.info("  Task started turn=\(turnIndex)")
            do {
                var response = try inference.chat(messages: taskHistory)
                chatLog.info("  chat() turn=\(turnIndex) chars=\(response.count)")

                // ── Agentic tool loop ─────────────────────────────────────────
                for iteration in 0..<AgentLoop.maxIterations {
                    guard AgentLoop.hasToolCall(response) else { break }
                    guard let toolCall = AgentLoop.parse(response) else { break }
                    chatLog.info("  tool call iter=\(iteration) name=\(toolCall.toolName)")

                    // Show any text the model emitted before the <tool_call> tag
                    let preamble = toolCall.textBefore
                    let toolMsgId: UUID = await MainActor.run {
                        if !preamble.isEmpty,
                           let idx = messages.firstIndex(where: { $0.id == targetId }) {
                            messages[idx].text = preamble
                        }
                        let toolMsg = Message(role: .tool(name: toolCall.toolName), text: "")
                        messages.append(toolMsg)
                        scrollToBottom()
                        return toolMsg.id
                    }

                    // Execute the tool
                    let toolResultVal: ToolResult
                    if let tool = ToolRegistry.shared.find(toolCall.toolName) {
                        toolResultVal = await tool.execute(toolCall.args)
                    } else {
                        toolResultVal = .text("Tool '\(toolCall.toolName)' not found.")
                    }
                    let toolResultText = toolResultVal.modelText

                    // Capture any chart image
                    if case .image(let img, _) = toolResultVal {
                        pendingChart = img
                    }
                    chatLog.info("  tool result: \(toolResultText.prefix(80))")

                    // Update tool bubble with result summary
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == toolMsgId }) {
                            messages[idx] = Message(role: .tool(name: toolCall.toolName),
                                                    text: toolResultText)
                        }
                        scrollToBottom()
                    }

                    // Append to history and add new assistant placeholder
                    taskHistory.append(InferenceMessage(role: "assistant", text: response))
                    taskHistory.append(AgentLoop.toolResultMessage(toolName: toolCall.toolName,
                                                                   result:   toolResultText))
                    let nextAssistantMsg = Message(role: .assistant, text: "")
                    let nextTargetId: UUID = await MainActor.run {
                        messages.append(nextAssistantMsg)
                        streamingId = nextAssistantMsg.id
                        scrollToBottom()
                        return nextAssistantMsg.id
                    }

                    // Call model again
                    response = try inference.chat(messages: taskHistory)
                    chatLog.info("  follow-up chat() iter=\(iteration) chars=\(response.count)")
                    // targetId for final update is now nextTargetId
                    _ = nextTargetId  // suppress unused warning; final update uses streamingId
                }

                // ── Final response ────────────────────────────────────────────
                taskHistory.append(InferenceMessage(role: "assistant", text: response))
                guard !Task.isCancelled else { return }
                let chartToAttach = pendingChart
                await MainActor.run {
                    // Update whichever assistant bubble is current (streamingId)
                    if let sid = streamingId,
                       let idx = messages.firstIndex(where: { $0.id == sid }) {
                        messages[idx].text       = response
                        messages[idx].chartImage = chartToAttach
                    }
                    inferenceHistory = taskHistory
                    scrollToBottom()
                }
            } catch {
                chatLog.error("  chat() error turn=\(turnIndex): \(error.localizedDescription)")
                let errText = error.localizedDescription
                // If send_message returned nil the C engine may be in a corrupted
                // state — even subsequent text turns will fail until a full reload.
                // Unload now so the UI correctly reflects the invalid engine state.
                let needsUnload = errText.contains("conversation_send_message returned nil")
                await MainActor.run {
                    if let sid = streamingId,
                       let idx = messages.firstIndex(where: { $0.id == sid }) {
                        messages[idx] = Message(role: .error, text: "⚠️ \(errText)")
                    }
                    if needsUnload {
                        dlog("send: engine corrupted after send_message nil — forcing unload")
                        appState.unloadModel()
                    }
                }
            }
            await MainActor.run {
                isGenerating = false; streamingId = nil; inferTask = nil
            }
        }
    }

    private func stopGeneration() {
        inferTask?.cancel()
        InferenceService.shared.cancelInference()
        dlog("stopGeneration() called")
    }

    private func scrollToBottom() {
        guard let last = messages.last else { return }
        DispatchQueue.main.async {
            withAnimation { scrollProxy?.scrollTo(last.id, anchor: .bottom) }
        }
    }

    // MARK: - Image helpers

    private func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let s = image.size
        guard s.width > maxDimension || s.height > maxDimension else { return image }
        let scale    = maxDimension / max(s.width, s.height)
        let newSize  = CGSize(width: s.width * scale, height: s.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    // MARK: - Background infer (URL scheme)

    private func runBackgroundInfer(prompt: String, callbackURL: URL?) {
        let inference = InferenceService.shared
        guard inference.isLoaded else { return }
        Task.detached(priority: .userInitiated) {
            var result = ""
            do {
                for try await chunk in inference.chatStream(
                    messages: [InferenceMessage(role: "user", text: prompt)]
                ) { result += chunk }
            } catch { result = error.localizedDescription }
            guard let callback = callbackURL else { return }
            if var comps = URLComponents(url: callback, resolvingAgainstBaseURL: false) {
                var items = comps.queryItems ?? []
                items.append(URLQueryItem(name: "response", value: result))
                comps.queryItems = items
                if let final = comps.url {
                    await MainActor.run { UIApplication.shared.open(final) }
                }
            }
        }
    }
}

// MARK: - ImagePickerView

private struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPick:     (UIImage) -> Void
    let onCancel:   () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType    = sourceType
        p.allowsEditing = false
        p.delegate      = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePickerView
        init(_ p: ImagePickerView) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onPick(img) } else { parent.onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}

// MARK: - ThinkingDots

private struct ThinkingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().frame(width: 8, height: 8)
                    .foregroundStyle(.secondary)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .opacity(phase == i ? 1.0 : 0.4)
                    .animation(.easeInOut(duration: 0.35), value: phase)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message:     Message
    let isStreaming: Bool

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .error:
            errorBubble
        case .code:
            codeBubble
        case .tool(let name):
            toolBubble(name: name)
        }
    }

    // ── User bubble ───────────────────────────────────────────────────────────
    private var userBubble: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 40)
            VStack(alignment: .trailing, spacing: 4) {
                if let img = message.image {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 180, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if !message.text.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(message.text)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // ── Assistant bubble ──────────────────────────────────────────────────────
    private var assistantBubble: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if isStreaming && message.text.isEmpty {
                        ThinkingDots()
                            .padding(.horizontal, 16).padding(.vertical, 12)
                    } else {
                        Text(message.text)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                    }
                }
                .background(Color(.secondarySystemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                if let chart = message.chartImage {
                    Image(uiImage: chart)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            Spacer(minLength: 40)
        }
    }

    // ── Error bubble ──────────────────────────────────────────────────────────
    private var errorBubble: some View {
        HStack {
            Text(message.text)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer(minLength: 40)
        }
    }

    // ── Code bubble ───────────────────────────────────────────────────────────
    private var codeBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Generated Python", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if isStreaming && message.text == "Generating Python code…" {
                    ThinkingDots().padding(.vertical, 4)
                } else {
                    Text(message.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            Spacer(minLength: 40)
        }
    }

    // ── Tool bubble ───────────────────────────────────────────────────────────
    private func toolBubble(name: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label(name, systemImage: "gearshape.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if message.text.isEmpty {
                    ThinkingDots().padding(.vertical, 2)
                } else {
                    Text(message.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(10)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            Spacer(minLength: 40)
        }
    }
}
