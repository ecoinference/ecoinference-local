// App-wide constants for AIServer.

class AppConstants {
  AppConstants._();

  static const String appName = 'Gemma4 Server';
  static const int defaultPort = 8080;
  static const String settingsKeyPort = 'server_port';
  static const String settingsKeySelectedModel = 'selected_model_id';
  static const String settingsKeyHfToken = 'hf_token';
  static const String settingsKeySetupDone = 'setup_done';

  /// Inference platform-channel name
  static const String inferenceChannel = 'com.gemma4.AIServer/inference';

  /// Platform-channel method names
  static const String methodLoadModel = 'loadModel';
  static const String methodRunInference = 'runInference';
  static const String methodUnloadModel = 'unloadModel';
  static const String methodIsModelLoaded = 'isModelLoaded';

  /// REST route paths
  static const String routeHealth = '/health';
  static const String routeModels = '/v1/models';
  static const String routeLoadModel = '/v1/models/load';
  static const String routeChatCompletions = '/v1/chat/completions';
  static const String routeCompletions = '/v1/completions';
}
