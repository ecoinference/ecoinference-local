import SwiftUI
import UIKit
import os.log

private let chatLog = Logger(subsystem: "ai.ecoinference.app", category: "ChatView")

// MARK: - Message model

private struct Message: Identifiable {
    let id           = UUID()
    let role         : Role
    var text         : String
    var image        : UIImage? = nil   // user messages: attached thumbnail for display
    var chartImage   : UIImage? = nil   // assistant messages: tool-generated chart
    var tier          : RouterService.Tier? = nil   // which tier produced this (assistant only)
    var sourcePrompt  : String? = nil   // user prompt that produced this response (assistant only)
    var sourceImage   : UIImage? = nil  // user-attached image that produced this response (assistant only)
    var routingReason : String? = nil   // why the router chose this tier (assistant only)

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
    // Set by stopGeneration() so the catch block below can tell a
    // user-requested cancellation (which surfaces as a "send_message
    // returned nil" error, since the local chat call is non-streaming) apart
    // from a genuine failure — a user-initiated stop shouldn't look like an
    // alarming error.
    @State private var userRequestedStop = false
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

    private var modelReady:        Bool { appState.modelLoaded && !appState.isLoading }
    private var isMultimodal:      Bool { InferenceService.shared.isMultimodal }
    private var sessionCloudCount: Int  {
        messages.filter { if case .assistant = $0.role { return $0.tier == .cloud && !$0.text.isEmpty } else { return false } }.count
    }

    // ── Regex: `use tool <request>` ───────────────────────────────────────────
    private static let toolCmdRe = try! NSRegularExpression(
        pattern: #"^use tool\s+(.+)$"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    var body: some View {
        NavigationStack {
        ZStack(alignment: .top) {
            // Fill the entire NavigationStack frame (including behind Dynamic
            // Island and below home indicator) so no black window shows through.
            EcoColors.background.ignoresSafeArea()

        VStack(spacing: 0) {

            // ── Compact title bar ─────────────────────────────────────────────
            // Safe area separates text from Dynamic Island — no top padding needed.
            EcoWordmark(fontSize: 22)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                .background(EcoColors.background.ignoresSafeArea(edges: .top))
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
                                message:          msg,
                                isStreaming:      msg.id == streamingId,
                                onRetryWithCloud: (msg.tier == .local && !isGenerating
                                                   && msg.id != streamingId
                                                   && msg.sourcePrompt != nil)
                                                  ? { retryWithCloud(sourceMsg: msg) }
                                                  : nil
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
            .background(EcoColors.background.ignoresSafeArea(edges: .bottom))
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        } // ZStack
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
                pendingImage              = resized(picked, maxDimension: 1024)
                ImageStore.shared.currentImage = pendingImage   // make available to edit_image tool
                showImagePicker = false
            } onCancel: { showImagePicker = false }
        }
        // ── Dismiss keyboard if the model unloads out from under the user ──────
        .onChange(of: appState.modelLoaded) { _, loaded in
            if !loaded { inputFocused = false }
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
                    if sessionCloudCount > 0 {
                        Label("\(sessionCloudCount) cloud", systemImage: "cloud.fill")
                            .font(.caption2)
                            .foregroundStyle(Color(red: 0x5E/255, green: 0x5C/255, blue: 0xE6/255))
                    }
                    Spacer()
                    if isGenerating {
                        Button {
                            stopGeneration()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                        }
                        .foregroundStyle(userRequestedStop ? .gray : .red)
                        .disabled(userRequestedStop)
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
                    // Guaranteed way to dismiss the keyboard — the interactive
                    // scroll-to-dismiss on the message list only works if there's
                    // enough scrollable content, and isn't discoverable. Found
                    // 2026-07-27: a user could get stuck with the keyboard up and
                    // no way to close it (had to force-quit) after the model
                    // auto-unloaded mid-chat. Never rely on a single dismissal
                    // path for the keyboard again.
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { inputFocused = false }
                        }
                    }

                Button(action: sendCurrentInput) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? EcoColors.green : Color.gray)
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
                // 1024 was too tight — a real generation for "plot a sine
                // wave" hit 7673 raw chars and got cut off mid-code, which
                // guaranteed a syntax error once execution was wired up
                // (2026-07-27, confirmed via device log character counts).
                let raw  = try inference.chat(
                    messages:    [InferenceMessage(role: "user", text: prompt)],
                    maxTokens:   2048,
                    temperature: 0.1
                )
                let hasOpenFence  = raw.range(of: "```python", options: .caseInsensitive) != nil
                let closeFenceIdx = hasOpenFence
                    ? raw.range(of: "```python", options: .caseInsensitive).flatMap {
                          raw.range(of: "```", range: $0.upperBound..<raw.endIndex)
                      }
                    : nil
                dlog("handleToolCommand: chat() returned — raw=\(raw.count) chars hasOpenFence=\(hasOpenFence) hasCloseFence=\(closeFenceIdx != nil) — tail: \(raw.suffix(300))")
                // Reset again so the tool call doesn't contaminate the next chat turn.
                inference.resetConversation()
                let code = PythonCommand.extractCode(from: raw) ?? raw
                dlog("handleToolCommand: extracted code (\(code.count) chars) — tail: \(code.suffix(300))")
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

                // Actually run the generated code on-device via the same
                // embedded PythonRunner the automatic run_python tool uses —
                // "use tool" previously only ever displayed the source, never
                // executed it, which made the command misleading to document.
                //
                // The generation can genuinely run out of token budget before
                // finishing (confirmed live, 2026-07-28: code cut off mid-line
                // at "plt." with no fence markers at all, so presence/absence
                // of a closing ``` isn't a reliable truncation signal). Running
                // known-incomplete code just produces a cryptic SyntaxError, so
                // detect the obvious case — code ending mid-statement — and say
                // so plainly instead of attempting it.
                let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                let danglingEndings: Set<Character> = [".", ",", "+", "-", "*", "/", "=", ":", "(", "[", "{", "\\"]
                if trimmedCode.isEmpty || danglingEndings.contains(trimmedCode.last!) {
                    dlog("handleToolCommand: code looks truncated (ends with '\(trimmedCode.last.map(String.init) ?? "empty")') — skipping execution")
                    await MainActor.run {
                        messages.append(Message(
                            role: .tool(name: "run_python"),
                            text: "⚠️ The generated code was cut off before finishing — try a shorter or simpler request."
                        ))
                        scrollToBottom()
                    }
                    await MainActor.run { isGenerating = false; streamingId = nil; inferTask = nil }
                    return
                }

                // The model can also decline or answer in prose instead of
                // writing code at all (e.g. "I can't help with that request.")
                // — every genuine script for this feature has at least one
                // function call or import, so the complete absence of both is
                // a reliable signal this isn't code, and running it would
                // just produce a confusing SyntaxError.
                let looksLikeCode = trimmedCode.contains("(") || trimmedCode.contains("import ")
                if !looksLikeCode {
                    dlog("handleToolCommand: response doesn't look like code — skipping execution")
                    await MainActor.run {
                        messages.append(Message(
                            role: .tool(name: "run_python"),
                            text: "⚠️ The model didn't return runnable code for that request — try rephrasing."
                        ))
                        scrollToBottom()
                    }
                    await MainActor.run { isGenerating = false; streamingId = nil; inferTask = nil }
                    return
                }

                let runningMsg = Message(role: .tool(name: "run_python"), text: "")
                let runningId  = runningMsg.id
                await MainActor.run {
                    messages.append(runningMsg)
                    scrollToBottom()
                }
                guard !Task.isCancelled else { dlog("handleToolCommand: cancelled before execute"); return }

                // Defensive timeout — generated code could contain a runaway
                // loop or an unexpectedly heavy computation. There's no clean
                // way to interrupt CPython mid-execution from here (it may
                // keep running in the background using CPU until it finishes
                // or the interpreter faults), but the user must never be left
                // staring at a stuck spinner indefinitely — see the earlier
                // stuck-keyboard lesson this session on always having a way out.
                // The preamble must be prepended to the code that actually RUNS, not
                // just described to the model. buildToolPrompt() only tells the model
                // that user_latitude/user_longitude/user_timezone are predefined —
                // without this they never exist at runtime, so every location- or
                // time-dependent `use tool` request died with "NameError: name
                // 'user_latitude' is not defined". TestView always did this correctly,
                // which is why its Python tests passed while the feature was broken.
                // The displayed code bubble stays preamble-free: it's plumbing.
                let runnableCode = (locPreamble.map { $0 + "\n" } ?? "") + code
                let result: ToolResult = await withTaskGroup(of: ToolResult?.self) { group in
                    group.addTask { await PythonRunner.execute(code: runnableCode) }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 30_000_000_000)
                        return nil
                    }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    if let first { return first }
                    dlog("handleToolCommand: execution timed out after 30s")
                    return .text("⚠️ Execution is taking longer than expected (30s+) — it may still be running in the background, but won't be shown here.")
                }
                dlog("handleToolCommand: execute() returned")
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == runningId }) {
                        if case .image(let img, let caption) = result {
                            messages[idx] = Message(role: .assistant, text: caption, chartImage: img)
                        } else {
                            messages[idx] = Message(role: .tool(name: "run_python"), text: result.displayText)
                        }
                    }
                    scrollToBottom()
                }
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
        userRequestedStop = false

        let turnIndex = messages.filter {
            if case .user = $0.role { return true }; return false
        }.count + 1
        chatLog.info("▶︎ send() turn=\(turnIndex) chars=\(text.count) hasImage=\(image != nil)")
        dlog("send() turn=\(turnIndex) text=\(text.prefix(60)) hasImage=\(image != nil)")

        // ── Router decision (before mutating messages/history) ─────────────────
        let decision = RouterService.shared.decide(
            prompt:             text,
            history:            inferenceHistory,
            hasImage:           image != nil,
            localSupportsImage: appState.imageInputEnabled
        )
        chatLog.info("  router tier=\(decision.tier.rawValue) rule=\(decision.ruleId ?? "default")")
        dlog("send() router tier=\(decision.tier.rawValue) reason=\(decision.reason)")

        // Snapshot prior visible turns for the cloud path — built BEFORE the new
        // user/assistant bubbles are appended below, and independent of
        // inferenceHistory (which only tracks what's actually been fed to the
        // local engine's KV-cache, so cloud turns must never touch it — mixing
        // them in would desync committedMessageCount on the next local turn).
        let cloudHistory = cloudHistoryMessages()

        // ── User bubble ───────────────────────────────────────────────────────
        messages.append(Message(role: .user, text: text, image: image))

        // ── Assistant placeholder ─────────────────────────────────────────────
        let assistantMsg = Message(role: .assistant, text: "", tier: decision.tier,
                                   sourcePrompt: decision.tier == .local ? text : nil,
                                   sourceImage: decision.tier == .local ? image : nil,
                                   routingReason: decision.reason)
        messages.append(assistantMsg)
        streamingId  = assistantMsg.id
        isGenerating = true
        scrollToBottom()

        if decision.tier == .cloud {
            sendToCloud(text: text, image: image, priorHistory: cloudHistory,
                       targetId: assistantMsg.id, systemOverride: systemOverride)
            return
        }

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
        // Blank text only reaches here when an image is attached (see the
        // `!text.isEmpty || pendingImage != nil` guard above) — a bare " " with
        // tool-calling available in the system prompt was leading the model to
        // attempt a bogus tool call instead of just describing the image.
        //
        // A custom question alongside an image ("What bird is this") was found
        // to reliably make the model claim no image was provided, even though
        // the engine trace confirms the vision encoder ran and prefill
        // succeeded — reproducible across fresh conversations (fixed seed=0 in
        // the bundle's sampler config), while the generic "Describe this
        // image." prompt always grounds correctly. Prepending an explicit
        // grounding cue nudges the model onto the same reliable path without
        // changing what the user sees in their own chat bubble.
        let sendText: String
        if text.isEmpty {
            sendText = image != nil ? "Describe this image." : " "
        } else if image != nil {
            sendText = "Looking at the attached image, \(text) Answer directly from what you " +
                       "see — you already have full vision of the image and do not need any tool for this."
        } else {
            sendText = text
        }
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
                    guard let toolCall = AgentLoop.parse(response) else {
                        // Tool-call tag present but unparseable after all repair
                        // attempts — never show the raw <tool_call>/JSON fragment
                        // to the user (mirrors Android AgentLoop.kt's fallback).
                        chatLog.error("  tool call detected but failed to parse: \(response.prefix(200))")
                        response = "Sorry, I couldn't parse the tool call."
                        break
                    }
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

                    // Update tool bubble with result summary — the human-facing
                    // display text, not the raw model-facing JSON (see
                    // ToolResult.displayText).
                    await MainActor.run {
                        if let idx = messages.firstIndex(where: { $0.id == toolMsgId }) {
                            messages[idx] = Message(role: .tool(name: toolCall.toolName),
                                                    text: toolResultVal.displayText)
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

                // If the loop hit the iteration cap while the model still wanted
                // to call another tool, don't let the raw tool-call fragment
                // reach the chat bubble — force one more no-more-tools turn.
                if AgentLoop.hasToolCall(response) {
                    chatLog.info("  tool budget exhausted after \(AgentLoop.maxIterations) iterations — forcing final turn")
                    taskHistory.append(InferenceMessage(role: "assistant", text: response))
                    taskHistory.append(InferenceMessage(role: "user", text: AgentLoop.budgetExhaustedNudge))
                    response = try inference.chat(messages: taskHistory)
                    if AgentLoop.hasToolCall(response) {
                        // Model ignored the nudge — still never show a raw tool-call fragment.
                        chatLog.error("  forced-final turn still contained a tool call: \(response.prefix(200))")
                        response = "I wasn't able to finish that within the tool budget — please try rephrasing."
                    }
                }

                // ── Final response ────────────────────────────────────────────
                taskHistory.append(InferenceMessage(role: "assistant", text: response))
                guard !Task.isCancelled else { return }
                let chartToAttach = pendingChart
                let capturedSourcePrompt = text
                await MainActor.run {
                    // Update whichever assistant bubble is current (streamingId)
                    if let sid = streamingId,
                       let idx = messages.firstIndex(where: { $0.id == sid }) {
                        messages[idx].text         = response
                        messages[idx].chartImage   = chartToAttach
                        messages[idx].sourcePrompt = capturedSourcePrompt
                    }
                    inferenceHistory = taskHistory
                    SettingsService.shared.lifetimeLocalCount += 1
                    scrollToBottom()
                }
            } catch {
                chatLog.error("  chat() error turn=\(turnIndex): \(error.localizedDescription)")
                let errText = error.localizedDescription
                // If send_message/generate_content returned nil the C engine may be
                // in a corrupted state — even subsequent text turns will fail until a
                // full reload. Unload now so the UI correctly reflects the invalid
                // engine state. Covers both the multimodal Conversation API
                // ("conversation_send_message returned nil") and the non-multimodal
                // Session API ("generate_content returned nil") — the latter can also
                // genuinely corrupt/exhaust the session's KV-cache, since
                // resetConversation() can't recreate a session for text-only models
                // (the SDK allows only one per engine lifetime — see
                // LiteRtLmEngine.resetConversation()'s doc comment), so repeated
                // resets silently accumulate real tokens until the model's compiled
                // context ceiling is exhausted.
                //
                // This is also how a user-requested Stop surfaces: the local chat
                // call is non-streaming/blocking, so cancelActiveSession()'s native
                // cancel_process() call makes send_message itself return nil rather
                // than the Swift Task's cancellation short-circuiting anything. Don't
                // show that expected case as an alarming error.
                let needsUnload = errText.contains("conversation_send_message returned nil") ||
                                  errText.contains("generate_content returned nil")
                let wasUserStop = userRequestedStop && needsUnload
                await MainActor.run {
                    if let sid = streamingId,
                       let idx = messages.firstIndex(where: { $0.id == sid }) {
                        messages[idx] = wasUserStop
                            ? Message(role: .assistant, text: "(Generation stopped — reloading model…)")
                            : Message(role: .error, text: "⚠️ \(errText)")
                    }
                    if needsUnload {
                        // Always unload on a nil return, even for a user-requested
                        // stop — confirmed via live device log (2026-07-27) that
                        // cancelling mid-prefill can leave the speculative-decoding
                        // "drafter" model corrupted (a subsequent turn failed with a
                        // genuine XNNPACK tensor-allocation error,
                        // llm_litert_mtp_drafter.cc), even though the cancellation
                        // itself completes cleanly. Skipping the unload here was a
                        // real regression, not just an unnecessary reload.
                        //
                        // Auto-reload the same model right after, rather than
                        // leaving the user stuck at an unloaded state — this is
                        // now a routine consequence of Stop, not a rare corruption
                        // case, so it shouldn't require a manual trip to Models.
                        let modelToReload = appState.loadedModelId
                        dlog("send: engine corrupted after send_message nil — forcing unload")
                        appState.unloadModel()
                        if let modelId = modelToReload {
                            appState.loadModel(modelId: modelId, useGpu: SettingsService.shared.useGpu)
                        }
                    }
                }
            }
            await MainActor.run {
                isGenerating = false; streamingId = nil; inferTask = nil
            }
        }
    }

    // MARK: - Cloud send (Gemini, router-selected)

    /// Visible prior turns converted for the cloud call. Deliberately separate
    /// from `inferenceHistory` — that array only tracks what's actually been
    /// fed to the local engine, and a cloud turn must never be spliced into it
    /// (see the comment in `send()`).
    private func cloudHistoryMessages() -> [InferenceMessage] {
        messages.compactMap { m -> InferenceMessage? in
            switch m.role {
            case .user:
                return InferenceMessage(role: "user", text: m.text)
            case .assistant:
                return m.text.isEmpty ? nil : InferenceMessage(role: "assistant", text: m.text)
            default:
                return nil   // skip tool/code/error bubbles — not meaningful cloud context
            }
        }
    }

    private func sendToCloud(
        text: String,
        image: UIImage?,
        priorHistory: [InferenceMessage],
        targetId: UUID,
        systemOverride: String?
    ) {
        let imageData      = image?.jpegData(compressionQuality: 0.85)
        var cloudMessages  = priorHistory
        cloudMessages.append(InferenceMessage(role: "user", text: text.isEmpty ? " " : text, imageData: imageData))
        let systemPrompt   = systemOverride ?? SettingsService.shared.systemPrompt

        inferTask = Task.detached(priority: .userInitiated) {
            do {
                let response = try await GeminiService.shared.chat(
                    messages:     cloudMessages,
                    systemPrompt: systemPrompt
                )
                chatLog.info("  cloud chat() chars=\(response.count)")
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == targetId }) {
                        messages[idx].text = response
                    }
                    SettingsService.shared.lifetimeCloudCount += 1
                    scrollToBottom()
                }
            } catch {
                let nsError = error as NSError
                let detail  = "domain=\(nsError.domain) code=\(nsError.code) desc=\(error.localizedDescription)"
                chatLog.error("  cloud chat() error: \(detail)")
                print("[GeminiService] error: \(detail)")
                await MainActor.run {
                    if let idx = messages.firstIndex(where: { $0.id == targetId }) {
                        messages[idx] = Message(role: .error, text: "⚠️ \(error.localizedDescription)", tier: .cloud)
                    }
                }
            }
            await MainActor.run {
                isGenerating = false; streamingId = nil; inferTask = nil
            }
        }
    }

    private func retryWithCloud(sourceMsg: Message) {
        guard let prompt = sourceMsg.sourcePrompt, !isGenerating else { return }

        // Build history up to (but not including) the message being retried
        let priorHistory: [InferenceMessage] = messages
            .prefix(while: { $0.id != sourceMsg.id })
            .compactMap { m -> InferenceMessage? in
                switch m.role {
                case .user:      return InferenceMessage(role: "user", text: m.text)
                case .assistant: return m.text.isEmpty ? nil : InferenceMessage(role: "assistant", text: m.text)
                default:         return nil
                }
            }

        let placeholder = Message(role: .assistant, text: "", tier: .cloud,
                                  routingReason: "Retried with cloud at your request.")
        messages.append(placeholder)
        streamingId  = placeholder.id
        isGenerating = true
        scrollToBottom()

        sendToCloud(text: prompt, image: sourceMsg.sourceImage, priorHistory: priorHistory,
                    targetId: placeholder.id, systemOverride: nil)
    }

    private func stopGeneration() {
        userRequestedStop = true
        // The underlying local chat call is non-streaming/blocking, so there's
        // a real delay (the native call has to actually notice cancel_process()
        // and return) before anything visibly changes — give immediate feedback
        // so the tap doesn't look like it did nothing.
        if let sid = streamingId, let idx = messages.firstIndex(where: { $0.id == sid }) {
            messages[idx].text = "Stopping…"
        }
        // Signal the native engine to stop BEFORE cancelling the Swift Task —
        // matches the fix needed on Android, where the reverse order raced
        // Conversation teardown against the still-running native generation
        // thread and crashed. iOS's conversation isn't torn down on Task
        // cancellation alone, so this is a correctness/ordering improvement
        // rather than a confirmed crash fix here.
        InferenceService.shared.cancelInference()
        inferTask?.cancel()
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
    let message:          Message
    let isStreaming:      Bool
    var onRetryWithCloud: (() -> Void)? = nil

    @State private var showRoutingReason = false

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
                        .background(EcoColors.green)
                        .foregroundStyle(EcoColors.darkInner)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // ── Assistant bubble ──────────────────────────────────────────────────────
    private var assistantBubble: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let tier = message.tier {
                    VStack(alignment: .leading, spacing: 4) {
                        tierBadge(tier)
                            .onTapGesture {
                                guard message.routingReason != nil else { return }
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    showRoutingReason.toggle()
                                }
                            }
                        if showRoutingReason, let reason = message.routingReason {
                            Text(reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
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
                        SaveableImageView(image: chart)
                    }
                }

                if let retry = onRetryWithCloud {
                    Button(action: retry) {
                        Label("Try with Cloud", systemImage: "cloud.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color(red: 0x5E/255, green: 0x5C/255, blue: 0xE6/255))
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 40)
        }
    }

    // ── Tier badge (Local / Cloud) ──────────────────────────────────────────────
    private func tierBadge(_ tier: RouterService.Tier) -> some View {
        let (label, icon, color): (String, String, Color) = tier == .cloud
            ? ("Cloud", "cloud.fill", .indigo)
            : ("Local", "cpu",        EcoColors.green)
        return Label(label, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
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

// MARK: - SaveableImageView

/// Displays a generated image with a save-to-photos button.
/// Tapping the image toggles the save button overlay; tapping "Save"
/// writes the image to the Camera Roll and shows a brief status badge.
private struct SaveableImageView: View {

    let image: UIImage

    @State private var showControls = false
    @State private var saveState: SaveState = .idle

    enum SaveState { case idle, saving, saved, denied, failed }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }

            if showControls || saveState != .idle {
                saveButton
                    .padding(8)
                    .transition(.opacity.combined(with: .scale))
            }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        switch saveState {
        case .idle, .saving:
            Button {
                Task { await performSave() }
            } label: {
                Label(
                    saveState == .saving ? "Saving…" : "Save",
                    systemImage: saveState == .saving ? "arrow.down.circle" : "square.and.arrow.down"
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
            }
            .disabled(saveState == .saving)

        case .saved:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())

        case .denied:
            Label("Access denied", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())

        case .failed:
            Label("Save failed", systemImage: "xmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
    }

    // @MainActor ensures all @State mutations stay on the main thread.
    // withAnimation is removed — SwiftUI animates @State changes implicitly.
    // Without @MainActor the PHPhotoLibrary suspension can resume on a
    // background thread, mutating @State off-main and blanking the view.
    @MainActor
    private func performSave() async {
        saveState = .saving
        let result = await PhotoSaver.save(image)
        switch result {
        case .saved:                saveState = .saved
        case .denied, .restricted:  saveState = .denied
        case .failed:               saveState = .failed
        }
        // Auto-hide after 2.5 s (4 s for denied so user has time to read it)
        let delay: UInt64 = saveState == .denied ? 4_000_000_000 : 2_500_000_000
        try? await Task.sleep(nanoseconds: delay)
        saveState   = .idle
        showControls = false
    }
}
