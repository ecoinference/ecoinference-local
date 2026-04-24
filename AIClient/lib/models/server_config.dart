/// Connection settings for the AIServer inference server.
class ServerConfig {
  const ServerConfig({
    this.host = '127.0.0.1',
    this.port = 8080,
    this.modelId = 'gemma4',
  });

  final String host;
  final int port;

  /// The model ID reported by the server at connect time (from /health).
  final String modelId;

  String get baseUrl => 'http://$host:$port';

  ServerConfig copyWith({String? host, int? port, String? modelId}) =>
      ServerConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        modelId: modelId ?? this.modelId,
      );
}
