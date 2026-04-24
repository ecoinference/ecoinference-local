/// Typed request/response models for the REST API.
/// Follows OpenAI schema so AIClient (and FlutterFlow) can stay provider-agnostic.

// ── Chat Completions ──────────────────────────────────────────────────────────

class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  factory ChatMessage.fromJson(Map<String, dynamic> j) =>
      ChatMessage(role: j['role'] as String, content: j['content'] as String);

  final String role;    // 'system' | 'user' | 'assistant'
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

class ChatCompletionRequest {
  const ChatCompletionRequest({
    required this.model,
    required this.messages,
    this.maxTokens = 512,
    this.temperature = 0.8,
    this.stream = false,
  });

  factory ChatCompletionRequest.fromJson(Map<String, dynamic> j) =>
      ChatCompletionRequest(
        model: j['model'] as String? ?? '',
        messages: (j['messages'] as List)
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        maxTokens: (j['max_tokens'] as int?) ?? 512,
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.8,
        stream: j['stream'] == true,
      );

  final String model;
  final List<ChatMessage> messages;
  final int maxTokens;
  final double temperature;
  /// When true the server responds with server-sent events (OpenAI streaming format).
  final bool stream;
}

class ChatCompletionResponse {
  const ChatCompletionResponse({
    required this.id,
    required this.model,
    required this.content,
    required this.promptTokens,
    required this.completionTokens,
  });

  final String id;
  final String model;
  final String content;
  final int promptTokens;
  final int completionTokens;

  Map<String, dynamic> toJson() => {
        'id': id,
        'object': 'chat.completion',
        'model': model,
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': content},
            'finish_reason': 'stop',
          }
        ],
        'usage': {
          'prompt_tokens': promptTokens,
          'completion_tokens': completionTokens,
          'total_tokens': promptTokens + completionTokens,
        },
      };
}

// ── Text Completions ──────────────────────────────────────────────────────────

class CompletionRequest {
  const CompletionRequest({
    required this.model,
    required this.prompt,
    this.maxTokens = 512,
    this.temperature = 0.8,
    this.stream = false,
  });

  factory CompletionRequest.fromJson(Map<String, dynamic> j) =>
      CompletionRequest(
        model: j['model'] as String? ?? '',
        prompt: j['prompt'] as String,
        maxTokens: (j['max_tokens'] as int?) ?? 512,
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.8,
        stream: j['stream'] == true,
      );

  final String model;
  final String prompt;
  final int maxTokens;
  final double temperature;
  /// When true the server responds with server-sent events (OpenAI streaming format).
  final bool stream;
}

class CompletionResponse {
  const CompletionResponse({
    required this.id,
    required this.model,
    required this.text,
  });

  final String id;
  final String model;
  final String text;

  Map<String, dynamic> toJson() => {
        'id': id,
        'object': 'text_completion',
        'model': model,
        'choices': [
          {'text': text, 'index': 0, 'finish_reason': 'stop'}
        ],
      };
}
