import 'dart:convert';

enum CloudSyncPhase { disabled, ready, syncing, synced, error, locked }

enum CloudSyncFailureKind {
  validation,
  credentials,
  passphrase,
  connectivity,
  incompatibleServer,
  corruptedData,
  conflict,
  cancelled,
  unknown,
}

class CloudSyncFailure implements Exception {
  const CloudSyncFailure(this.kind, this.message, {this.statusCode});

  final CloudSyncFailureKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class S3SyncConfig {
  const S3SyncConfig({
    required this.endpoint,
    required this.bucket,
    this.region = 'us-east-1',
    this.prefix = 'localmind',
    this.pathStyle = true,
    this.allowInsecureHttp = false,
    this.enabled = false,
  });

  final String endpoint;
  final String bucket;
  final String region;
  final String prefix;
  final bool pathStyle;
  final bool allowInsecureHttp;
  final bool enabled;

  Uri get endpointUri => Uri.parse(endpoint);

  String? validate() {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid S3 endpoint URL.';
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      return 'The endpoint must use HTTPS or HTTP.';
    }
    if (uri.scheme == 'http' && !allowInsecureHttp) {
      return 'Confirm insecure HTTP before continuing.';
    }
    if (bucket.trim().isEmpty || region.trim().isEmpty) {
      return 'Bucket and region are required.';
    }
    return null;
  }

  S3SyncConfig copyWith({
    String? endpoint,
    String? bucket,
    String? region,
    String? prefix,
    bool? pathStyle,
    bool? allowInsecureHttp,
    bool? enabled,
  }) {
    return S3SyncConfig(
      endpoint: endpoint ?? this.endpoint,
      bucket: bucket ?? this.bucket,
      region: region ?? this.region,
      prefix: prefix ?? this.prefix,
      pathStyle: pathStyle ?? this.pathStyle,
      allowInsecureHttp: allowInsecureHttp ?? this.allowInsecureHttp,
      enabled: enabled ?? this.enabled,
    );
  }

  factory S3SyncConfig.fromJson(Map<String, dynamic> json) => S3SyncConfig(
    endpoint: json['endpoint'] as String? ?? '',
    bucket: json['bucket'] as String? ?? '',
    region: json['region'] as String? ?? 'us-east-1',
    prefix: json['prefix'] as String? ?? 'localmind',
    pathStyle: json['pathStyle'] as bool? ?? true,
    allowInsecureHttp: json['allowInsecureHttp'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'endpoint': endpoint,
    'bucket': bucket,
    'region': region,
    'prefix': prefix,
    'pathStyle': pathStyle,
    'allowInsecureHttp': allowInsecureHttp,
    'enabled': enabled,
  };
}

class CloudSyncCredentials {
  const CloudSyncCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    this.sessionToken,
  });

  final String accessKeyId;
  final String secretAccessKey;
  final String? sessionToken;

  bool get isValid =>
      accessKeyId.trim().isNotEmpty && secretAccessKey.trim().isNotEmpty;
}

class CloudSyncStatus {
  const CloudSyncStatus({
    this.phase = CloudSyncPhase.disabled,
    this.lastSyncedAt,
    this.message,
    this.conflictCount = 0,
    this.warnings = const [],
  });

  final CloudSyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? message;
  final int conflictCount;
  final List<String> warnings;

  CloudSyncStatus copyWith({
    CloudSyncPhase? phase,
    DateTime? lastSyncedAt,
    String? message,
    bool clearMessage = false,
    int? conflictCount,
    List<String>? warnings,
  }) => CloudSyncStatus(
    phase: phase ?? this.phase,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    message: clearMessage ? null : (message ?? this.message),
    conflictCount: conflictCount ?? this.conflictCount,
    warnings: warnings ?? this.warnings,
  );
}

class CloudSyncSnapshot {
  const CloudSyncSnapshot({
    required this.deviceId,
    required this.revision,
    required this.updatedAt,
    required this.payload,
    this.tombstones = const {},
  });

  final String deviceId;
  final int revision;
  final DateTime updatedAt;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> tombstones;

  factory CloudSyncSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != 1 ||
        json['payload'] is! Map ||
        json['deviceId'] is! String ||
        (json['deviceId'] as String).length < 8 ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        json['updatedAt'] is! String) {
      throw const FormatException('Unsupported cloud sync snapshot');
    }
    final payload = Map<String, dynamic>.from(json['payload'] as Map);
    _validatePayload(payload);
    final tombstones = json['tombstones'] is Map
        ? Map<String, dynamic>.from(json['tombstones'] as Map)
        : <String, dynamic>{};
    for (final entry in tombstones.entries) {
      if (!_collections.contains(entry.key) ||
          entry.value is! List ||
          !(entry.value as List).every((value) => value is String)) {
        throw const FormatException('Invalid cloud sync tombstones');
      }
    }
    return CloudSyncSnapshot(
      deviceId: json['deviceId'] as String,
      revision: json['revision'] as int,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      payload: payload,
      tombstones: tombstones,
    );
  }

  static const _collections = {
    'conversations',
    'messages',
    'personas',
    'savedMessages',
    'savedMessageFolders',
    'conversationFolders',
  };

  static const _settingKeys = {
    'temperature',
    'topP',
    'maxTokens',
    'contextLength',
    'themeMode',
    'fontSize',
    'showSystemMessages',
    'hapticFeedbackEnabled',
    'sendOnEnter',
    'showDataIndicator',
    'autoGenerateTitle',
    'streamingEnabled',
    'defaultPersonaId',
    'mcpEnabled',
    'newChatMcpEnabled',
    'codeThemeDark',
    'codeThemeLight',
    'preferredBackend',
    'ttsEngine',
    'ttsVoiceId',
    'ttsSpeed',
    'kittenTtsModelVariant',
    'autoSpeakEnabled',
    'conciseVoiceResponsesEnabled',
    'ttsProcessMarkdown',
    'ttsSkipSeconds',
    'smartReplyEnabled',
    'aiUserResponseEnabled',
    'localeCode',
    'unloadModelsBeforeLoad',
    'tempChatKeyboardIncognito',
    'resumeLastChat',
    'imageCompressionEnabled',
    'imageCompressionLevel',
    'smartRepliesUsePersona',
    'keepPersonaOnNewChat',
    'roleSwapButtonEnabled',
    'showSystemMessagesInChat',
  };

  static void _validatePayload(Map<String, dynamic> payload) {
    if (payload['version'] != 1 ||
        payload['type'] != 'cloudSync' ||
        payload['settings'] is! Map ||
        !(payload['settings'] as Map).keys.every(
          (key) => key is String && _settingKeys.contains(key),
        )) {
      throw const FormatException('Invalid cloud sync payload');
    }
    for (final collection in _collections) {
      final records = payload[collection];
      if (records is! List ||
          !records.every(
            (record) =>
                record is Map &&
                record['id'] is String &&
                (record['id'] as String).isNotEmpty,
          )) {
        throw FormatException('Invalid cloud sync collection: $collection');
      }
      final ids = records
          .map((record) => (record as Map)['id'] as String)
          .toList();
      if (ids.toSet().length != ids.length) {
        throw FormatException('Duplicate IDs in cloud collection: $collection');
      }
    }
    final conversations = {
      for (final record in payload['conversations'] as List)
        (record as Map)['id'] as String,
    };
    if ((payload['conversations'] as List).any(
          (record) => (record as Map)['isTemporary'] == true,
        ) ||
        (payload['personas'] as List).any(
          (record) => (record as Map)['isBuiltIn'] == true,
        )) {
      throw const FormatException('Cloud payload contains excluded records');
    }
    bool validDate(dynamic value) =>
        value is String && DateTime.tryParse(value) != null;
    for (final raw in payload['conversations'] as List) {
      final record = raw as Map;
      if (!validDate(record['createdAt']) || !validDate(record['updatedAt'])) {
        throw const FormatException('Invalid cloud conversation');
      }
    }
    for (final raw in payload['personas'] as List) {
      final record = raw as Map;
      if (record['name'] is! String ||
          !validDate(record['createdAt']) ||
          !validDate(record['updatedAt'])) {
        throw const FormatException('Invalid cloud persona');
      }
    }
    for (final collection in const [
      'savedMessageFolders',
      'conversationFolders',
    ]) {
      for (final raw in payload[collection] as List) {
        final record = raw as Map;
        if (record['name'] is! String || !validDate(record['createdAt'])) {
          throw FormatException('Invalid cloud folder: $collection');
        }
      }
    }
    for (final raw in payload['savedMessages'] as List) {
      final record = raw as Map;
      if (record['sourceMessageId'] is! String ||
          record['conversationId'] is! String ||
          !validDate(record['savedAt'])) {
        throw const FormatException('Invalid cloud saved message');
      }
    }
    for (final raw in payload['messages'] as List) {
      final message = raw as Map;
      if (message['conversationId'] is! String ||
          (message['conversationId'] as String).isEmpty ||
          !conversations.contains(message['conversationId']) ||
          !validDate(message['createdAt']) ||
          (message['attachmentPaths'] != null &&
              (message['attachmentPaths'] is! List ||
                  !(message['attachmentPaths'] as List).every(
                    (path) =>
                        path is String &&
                        RegExp(
                          r'^cloud://[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$',
                        ).hasMatch(path),
                  )))) {
        throw const FormatException('Invalid cloud sync message');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'deviceId': deviceId,
    'revision': revision,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'payload': payload,
    'tombstones': tombstones,
  };

  String encode() => jsonEncode(toJson());
}

class CloudSyncRemoteState {
  const CloudSyncRemoteState({required this.bytes, this.etag});

  final List<int> bytes;
  final String? etag;
}
