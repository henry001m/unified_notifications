class MqttConfig {
  const MqttConfig({
    required this.broker,
    required this.port,
    required this.topicBase,
    this.username,
    this.password,
    this.useTls = false,
    this.keepAliveSeconds = 120,
    this.clientIdPrefix = 'unified',
    this.maxReconnectAttempts = 10,
    this.reconnectDelaySeconds = 5,
  });

  final String broker;
  final int port;
  final String topicBase;
  final String? username;
  final String? password;
  final bool useTls;
  final int keepAliveSeconds;
  final String clientIdPrefix;
  final int maxReconnectAttempts;
  final int reconnectDelaySeconds;

  Map<String, dynamic> toJson() {
    return {
      'broker': broker,
      'port': port,
      'topicBase': topicBase,
      'username': username,
      'password': password,
      'useTls': useTls,
      'keepAliveSeconds': keepAliveSeconds,
      'clientIdPrefix': clientIdPrefix,
    };
  }

  factory MqttConfig.fromJson(Map<String, dynamic> json) {
    return MqttConfig(
      broker: json['broker']?.toString() ?? '',
      port: (json['port'] as num?)?.toInt() ?? 1883,
      topicBase: json['topicBase']?.toString() ?? '',
      username: json['username']?.toString(),
      password: json['password']?.toString(),
      useTls: json['useTls'] == true,
      keepAliveSeconds: (json['keepAliveSeconds'] as num?)?.toInt() ?? 120,
      clientIdPrefix: json['clientIdPrefix']?.toString() ?? 'unified',
    );
  }
}
