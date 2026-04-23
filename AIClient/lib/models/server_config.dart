/// Connection settings for the AIServer inference server.
class ServerConfig {
  const ServerConfig({
    this.host = '127.0.0.1',
    this.port = 8080,
  });

  final String host;
  final int port;

  String get baseUrl => 'http://$host:$port';

  ServerConfig copyWith({String? host, int? port}) => ServerConfig(
        host: host ?? this.host,
        port: port ?? this.port,
      );
}
