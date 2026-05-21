enum MessageRole { user, assistant, system, tool }

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.toolName,
    this.imageDataUrl,
    this.htmlContent,
    this.attachedImageBase64,
  }) : timestamp = timestamp ?? DateTime.now();

  final MessageRole role;
  final String content;
  final DateTime timestamp;

  /// Set for [MessageRole.tool] messages — the name of the tool that ran.
  final String? toolName;

  /// Base64 PNG data URL for image tool results (not persisted).
  final String? imageDataUrl;

  /// Full HTML string for interactive chart results (not persisted).
  final String? htmlContent;

  /// Raw base64-encoded JPEG attached by the user before sending.
  /// Only set on [MessageRole.user] messages. Not persisted to disk — the
  /// thumbnail is shown in the current session but lost on app restart.
  final String? attachedImageBase64;

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isTool => role == MessageRole.tool;

  /// Serialises to the OpenAI-style JSON sent to the server.
  ///
  /// When [attachedImageBase64] is set the content is a multimodal array:
  /// ```json
  /// [
  ///   {"type": "text",      "text": "…"},
  ///   {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64,…"}}
  /// ]
  /// ```
  ///
  /// Tool result turns are sent as [role: "user"] because Gemma has no native
  /// tool role — the model understands them from the "[Tool result: …]" prefix
  /// injected by [AgentLoop.toolResultMessage].
  /// Tool UI messages ([role: "tool"]) are never sent to the server.
  Map<String, dynamic> toApiJson() {
    final effectiveRole = (role == MessageRole.tool) ? 'user' : role.name;

    if (attachedImageBase64 != null && role == MessageRole.user) {
      return {
        'role': effectiveRole,
        'content': [
          // A non-empty text part is required by most vision-capable servers.
          {'type': 'text', 'text': content.isNotEmpty ? content : ' '},
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,$attachedImageBase64',
            },
          },
        ],
      };
    }

    return {'role': effectiveRole, 'content': content};
  }

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        'timestamp': timestamp.millisecondsSinceEpoch,
        if (toolName != null) 'tool_name': toolName,
        // imageDataUrl, htmlContent, and attachedImageBase64 are not persisted
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Guard against unknown roles (e.g. from older saves before 'tool' existed).
    final roleName = json['role'] as String? ?? 'user';
    final role = MessageRole.values.asNameMap()[roleName] ?? MessageRole.user;
    return ChatMessage(
      role: role,
      content: json['content'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      toolName: json['tool_name'] as String?,
    );
  }
}
