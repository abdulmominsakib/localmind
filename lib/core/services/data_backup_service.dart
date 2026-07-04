import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/enums.dart';
import '../storage/entities.dart';
import 'data_backup_import_helpers.dart';
import '../../features/chat/data/models/message.dart';
import '../../features/conversations/data/models/conversation.dart';
import '../../features/personas/data/models/persona.dart';
import '../../features/servers/data/models/server.dart';
import '../../objectbox.g.dart';

class DataBackupService {
  Map<String, dynamic> _messageToMap(Message message) => {
        'id': message.id,
        'conversationId': message.conversationId,
        'role': message.role.name,
        'content': message.content,
        'createdAt': message.createdAt.toIso8601String(),
        'status': message.status.name,
        'modelId': message.modelId,
        'tokenCount': message.tokenCount,
        'errorMessage': message.errorMessage,
        'attachmentPaths': message.attachmentPaths,
        'generationTimeMs': message.generationTimeMs,
        'reasoningContent': message.reasoningContent,
        'toolCallId': message.toolCallId,
        'isProcessing': message.isProcessing,
        'toolSessionId': message.toolSessionId,
        'variantGroupId': message.variantGroupId,
        'variantIndex': message.variantIndex,
        'threadOrder': message.threadOrder,
        'isActiveVariant': message.isActiveVariant,
        'parentMessageId': message.parentMessageId,
      };

  Map<String, dynamic> _conversationToMap(Conversation domain) => {
        'id': domain.id,
        'title': domain.title,
        'createdAt': domain.createdAt.toIso8601String(),
        'updatedAt': domain.updatedAt.toIso8601String(),
        'isPinned': domain.isPinned,
        'personaId': domain.personaId,
        'serverId': domain.serverId,
        'modelId': domain.modelId,
        'messageCount': domain.messageCount,
        'lastMessagePreview': domain.lastMessagePreview,
        'systemPrompt': domain.systemPrompt,
        'temperature': domain.temperature,
        'topP': domain.topP,
        'maxTokens': domain.maxTokens,
        'contextLength': domain.contextLength,
        'mcpEnabled': domain.mcpEnabled,
        'smartReplies': domain.smartReplies,
        'smartRepliesLastMessageId': domain.smartRepliesLastMessageId,
        'folderId': domain.folderId,
      };

  List<Map<String, dynamic>> _exportSavedMessages(Store store) {
    final box = store.box<SavedMessageEntity>();
    return box.getAll().map((e) {
      return {
        'id': e.id,
        'sourceMessageId': e.sourceMessageId,
        'conversationId': e.conversationId,
        'conversationTitle': e.conversationTitle,
        'roleIndex': e.roleIndex,
        'content': e.content,
        'modelId': e.modelId,
        'folderId': e.folderId,
        'savedAt': e.savedAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportSavedMessageFolders(Store store) {
    final box = store.box<SavedMessageFolderEntity>();
    return box.getAll().map((e) {
      return {
        'id': e.id,
        'name': e.name,
        'sortOrder': e.sortOrder,
        'createdAt': e.createdAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportServers(Store store) {
    return store.box<ServerEntity>().getAll().map((entity) {
      final server = entity.toDomain();
      return {
        'id': server.id,
        'name': server.name,
        'type': server.type.name,
        'host': server.host,
        'port': server.port,
        'apiKey': server.apiKey,
        'isDefault': server.isDefault,
        'createdAt': server.createdAt.toIso8601String(),
        'lastConnectedAt': server.lastConnectedAt.toIso8601String(),
        'status': server.status.name,
        'iconName': server.iconName,
        'pathPrefix': server.pathPrefix,
      };
    }).toList();
  }

  Map<String, dynamic>? _readModelMetadata(SharedPreferences? prefs) {
    if (prefs == null) return null;
    final raw = prefs.getString('modelMetadata');
    if (raw == null || raw.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> exportAll(Store store, {SharedPreferences? prefs}) {
    final convBox = store.box<ConversationEntity>();
    final messageBox = store.box<MessageEntity>();
    final personaBox = store.box<PersonaEntity>();

    final conversations =
        convBox.getAll().map((e) => _conversationToMap(e.toDomain())).toList();
    final messages =
        messageBox.getAll().map((e) => _messageToMap(e.toDomain())).toList();

    final personas = personaBox
        .getAll()
        .where((entity) => !entity.isBuiltIn)
        .map((entity) {
          final persona = entity.toDomain();
          return {
            'id': persona.id,
            'name': persona.name,
            'emoji': persona.emoji,
            'systemPrompt': persona.systemPrompt,
            'description': persona.description,
            'isBuiltIn': persona.isBuiltIn,
            'createdAt': persona.createdAt.toIso8601String(),
            'updatedAt': persona.updatedAt.toIso8601String(),
            'category': persona.category,
            'preferredParams': persona.preferredParams,
          };
        })
        .toList();

    final modelMetadata = _readModelMetadata(prefs);
    return {
      'version': 3,
      'exportedAt': DateTime.now().toIso8601String(),
      'conversations': conversations,
      'messages': messages,
      'personas': personas,
      'savedMessages': _exportSavedMessages(store),
      'savedMessageFolders': _exportSavedMessageFolders(store),
      'servers': _exportServers(store),
      if (modelMetadata != null) 'modelMetadata': modelMetadata,
    };
  }

  Map<String, dynamic> exportConversations(Store store) {
    final all = exportAll(store);
    return {
      'version': 3,
      'type': 'conversations',
      'exportedAt': all['exportedAt'],
      'conversations': all['conversations'],
      'messages': all['messages'],
      'savedMessages': all['savedMessages'],
      'savedMessageFolders': all['savedMessageFolders'],
    };
  }

  Map<String, dynamic> exportConversation(Store store, String conversationId) {
    final all = exportAll(store);
    final conversations = (all['conversations'] as List)
        .where((c) => (c as Map)['id'] == conversationId)
        .toList();
    final messages = (all['messages'] as List)
        .where((m) => (m as Map)['conversationId'] == conversationId)
        .toList();
    final savedMessages = (all['savedMessages'] as List)
        .where((m) => (m as Map)['conversationId'] == conversationId)
        .toList();
    final folderIds = savedMessages
        .map((m) => (m as Map)['folderId'] as String?)
        .whereType<String>()
        .toSet();
    final savedMessageFolders = (all['savedMessageFolders'] as List)
        .where((f) => folderIds.contains((f as Map)['id']))
        .toList();

    return {
      'version': 3,
      'type': 'conversation',
      'exportedAt': all['exportedAt'],
      'conversations': conversations,
      'messages': messages,
      'savedMessages': savedMessages,
      'savedMessageFolders': savedMessageFolders,
    };
  }

  Map<String, dynamic> exportConversationsForIds(
    Store store,
    Set<String> conversationIds,
  ) {
    final all = exportAll(store);
    final conversations = (all['conversations'] as List)
        .where((c) => conversationIds.contains((c as Map)['id']))
        .toList();
    final messages = (all['messages'] as List)
        .where((m) => conversationIds.contains((m as Map)['conversationId']))
        .toList();
    final savedMessages = (all['savedMessages'] as List)
        .where(
          (m) => conversationIds.contains((m as Map)['conversationId']),
        )
        .toList();
    final folderIds = savedMessages
        .map((m) => (m as Map)['folderId'] as String?)
        .whereType<String>()
        .toSet();
    final savedMessageFolders = (all['savedMessageFolders'] as List)
        .where((f) => folderIds.contains((f as Map)['id']))
        .toList();

    return {
      'version': 3,
      'type': 'conversations',
      'exportedAt': all['exportedAt'],
      'conversations': conversations,
      'messages': messages,
      'savedMessages': savedMessages,
      'savedMessageFolders': savedMessageFolders,
    };
  }

  String exportConversationsForIdsAsJson(
    Store store,
    Set<String> conversationIds,
  ) =>
      const JsonEncoder.withIndent('  ')
          .convert(exportConversationsForIds(store, conversationIds));

  Map<String, dynamic> exportPersonas(Store store) {
    final all = exportAll(store);
    return {
      'version': 3,
      'type': 'personas',
      'exportedAt': all['exportedAt'],
      'personas': all['personas'],
    };
  }

  Map<String, dynamic> exportSettings(
    String settingsJson, {
    Store? store,
    SharedPreferences? prefs,
  }) {
    final map = <String, dynamic>{
      'version': 3,
      'type': 'settings',
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': jsonDecode(settingsJson),
    };
    if (store != null) {
      map['servers'] = _exportServers(store);
    }
    final metadata = _readModelMetadata(prefs);
    if (metadata != null) {
      map['modelMetadata'] = metadata;
    }
    return map;
  }

  String exportConversationsAsJson(Store store) =>
      const JsonEncoder.withIndent('  ').convert(exportConversations(store));

  String exportConversationAsJson(Store store, String conversationId) =>
      const JsonEncoder.withIndent('  ')
          .convert(exportConversation(store, conversationId));

  String exportPersonasAsJson(Store store) =>
      const JsonEncoder.withIndent('  ').convert(exportPersonas(store));

  String exportSettingsAsJson(
    String settingsJson, {
    Store? store,
    SharedPreferences? prefs,
  }) =>
      const JsonEncoder.withIndent('  ').convert(
        exportSettings(settingsJson, store: store, prefs: prefs),
      );

  ArchiveFile _jsonArchiveFile(String name, String json) {
    final bytes = utf8.encode(json);
    return ArchiveFile(name, bytes.length, bytes);
  }

  List<int> exportAllZip(
    Store store,
    String settingsJson, {
    SharedPreferences? prefs,
  }) {
    final archive = Archive()
      ..addFile(
        _jsonArchiveFile(
          'conversations.json',
          exportConversationsAsJson(store),
        ),
      )
      ..addFile(
        _jsonArchiveFile('personas.json', exportPersonasAsJson(store)),
      )
      ..addFile(
        _jsonArchiveFile(
          'settings.json',
          exportSettingsAsJson(settingsJson, store: store, prefs: prefs),
        ),
      );
    return ZipEncoder().encode(archive);
  }

  String exportAllAsJson(Store store, {SharedPreferences? prefs}) {
    return const JsonEncoder.withIndent('  ')
        .convert(exportAll(store, prefs: prefs));
  }

  Future<void> importFromJson(Store store, String jsonString) async {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Invalid backup format');
    }

    // Imported attachment paths are restored verbatim onto Message records
    // and later opened directly as files (image/text preview), so a
    // crafted backup could otherwise point them at arbitrary files already
    // readable by this app. Only accept paths that resolve inside our own
    // attachments directory.
    final appDir = await getApplicationDocumentsDirectory();
    final attachmentsDir = p.normalize(p.join(appDir.path, 'attachments'));

    await store.runInTransactionAsync(TxMode.write, (store, data) {
      final (decoded, attachmentsDir) = data;
      final convBox = store.box<ConversationEntity>();
      final messageBox = store.box<MessageEntity>();
      final personaBox = store.box<PersonaEntity>();
      final serverBox = store.box<ServerEntity>();
      final savedBox = store.box<SavedMessageEntity>();
      final savedFolderBox = store.box<SavedMessageFolderEntity>();

      final personas = decoded['personas'];
      if (personas is List) {
        for (final item in personas) {
          if (item is! Map) continue;
          final id = backupImportString(item['id']);
          final name = backupImportString(item['name']);
          final createdAt = backupImportDateTime(item['createdAt']);
          final updatedAt = backupImportDateTime(item['updatedAt']);
          if (id == null || name == null || createdAt == null || updatedAt == null) {
            continue;
          }
          final persona = Persona(
            id: id,
            name: name,
            emoji: item['emoji'] as String? ?? '🤖',
            systemPrompt: item['systemPrompt'] as String? ?? '',
            description: item['description'] as String?,
            isBuiltIn: item['isBuiltIn'] as bool? ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt,
            category: item['category'] as String?,
            preferredParams: item['preferredParams'] is Map
                ? Map<String, dynamic>.from(item['preferredParams'] as Map)
                : null,
          );
          final query =
              personaBox.query(PersonaEntity_.id.equals(persona.id)).build();
          final existing = query.findFirst();
          query.close();
          final entity = PersonaEntity.fromDomain(persona);
          if (existing != null) entity.internalId = existing.internalId;
          personaBox.put(entity);
        }
      }

      final servers = decoded['servers'];
      if (servers is List) {
        for (final item in servers) {
          if (item is! Map) continue;
          final id = backupImportString(item['id']);
          final name = backupImportString(item['name']);
          final createdAt = backupImportDateTime(item['createdAt']);
          final lastConnectedAt = backupImportDateTime(item['lastConnectedAt']);
          if (id == null ||
              name == null ||
              createdAt == null ||
              lastConnectedAt == null) {
            continue;
          }
          final server = Server(
            id: id,
            name: name,
            type: ServerType.values.byName(item['type'] as String? ?? 'lmStudio'),
            host: item['host'] as String? ?? 'localhost',
            port: item['port'] as int? ?? 1234,
            apiKey: item['apiKey'] as String?,
            isDefault: item['isDefault'] as bool? ?? false,
            createdAt: createdAt,
            lastConnectedAt: lastConnectedAt,
            status: ConnectionStatus.values.byName(
              item['status'] as String? ?? 'disconnected',
            ),
            iconName: item['iconName'] as String?,
            pathPrefix: item['pathPrefix'] as String?,
          );
          final query = serverBox.query(ServerEntity_.id.equals(server.id)).build();
          final existing = query.findFirst();
          query.close();
          final entity = ServerEntity.fromDomain(server);
          if (existing != null) entity.internalId = existing.internalId;
          serverBox.put(entity);
        }
      }

      final savedFolders = decoded['savedMessageFolders'];
      if (savedFolders is List) {
        for (final item in savedFolders) {
          if (item is! Map) continue;
          final id = backupImportString(item['id']);
          final folderName = backupImportString(item['name']);
          final createdAt = backupImportDateTime(item['createdAt']);
          if (id == null || folderName == null || createdAt == null) continue;
          final entity = SavedMessageFolderEntity(
            id: id,
            name: folderName,
            sortOrder: item['sortOrder'] as int? ?? 0,
            createdAt: createdAt,
          );
          final query = savedFolderBox
              .query(SavedMessageFolderEntity_.id.equals(entity.id))
              .build();
          final existing = query.findFirst();
          query.close();
          if (existing != null) entity.internalId = existing.internalId;
          savedFolderBox.put(entity);
        }
      }

      final savedMessages = decoded['savedMessages'];
      if (savedMessages is List) {
        for (final item in savedMessages) {
          if (item is! Map) continue;
          final id = backupImportString(item['id']);
          final sourceMessageId = backupImportString(item['sourceMessageId']);
          final conversationId = backupImportString(item['conversationId']);
          final savedAt = backupImportDateTime(item['savedAt']);
          if (id == null ||
              sourceMessageId == null ||
              conversationId == null ||
              savedAt == null) {
            continue;
          }
          final entity = SavedMessageEntity(
            id: id,
            sourceMessageId: sourceMessageId,
            conversationId: conversationId,
            conversationTitle: item['conversationTitle'] as String? ?? 'Chat',
            roleIndex: item['roleIndex'] as int? ?? 0,
            content: item['content'] as String? ?? '',
            modelId: item['modelId'] as String?,
            folderId: item['folderId'] as String?,
            savedAt: savedAt,
          );
          final query =
              savedBox.query(SavedMessageEntity_.id.equals(entity.id)).build();
          final existing = query.findFirst();
          query.close();
          if (existing != null) entity.internalId = existing.internalId;
          savedBox.put(entity);
        }
      }

      final conversations = decoded['conversations'];
      if (conversations is List) {
        for (final item in conversations) {
          if (item is! Map) continue;
          final id = backupImportString(item['id']);
          final createdAt = backupImportDateTime(item['createdAt']);
          final updatedAt = backupImportDateTime(item['updatedAt']);
          if (id == null || createdAt == null || updatedAt == null) continue;
          final conversation = Conversation(
            id: id,
            title: item['title'] as String? ?? 'Imported Chat',
            createdAt: createdAt,
            updatedAt: updatedAt,
            isPinned: item['isPinned'] as bool? ?? false,
            personaId: item['personaId'] as String?,
            serverId: item['serverId'] as String?,
            modelId: item['modelId'] as String?,
            messageCount: item['messageCount'] as int? ?? 0,
            lastMessagePreview: item['lastMessagePreview'] as String?,
            systemPrompt: item['systemPrompt'] as String?,
            temperature: (item['temperature'] as num?)?.toDouble(),
            topP: (item['topP'] as num?)?.toDouble(),
            maxTokens: item['maxTokens'] as int?,
            contextLength: item['contextLength'] as int?,
            mcpEnabled: item['mcpEnabled'] as bool?,
            smartReplies: item['smartReplies'] is List
                ? List<String>.from(item['smartReplies'] as List)
                : null,
            smartRepliesLastMessageId:
                item['smartRepliesLastMessageId'] as String?,
            folderId: item['folderId'] as String?,
          );
          final query =
              convBox.query(ConversationEntity_.id.equals(conversation.id)).build();
          final existing = query.findFirst();
          query.close();
          final entity = ConversationEntity.fromDomain(conversation);
          if (existing != null) entity.internalId = existing.internalId;
          convBox.put(entity);
        }
      }

      final messages = decoded['messages'];
      if (messages is List) {
        for (final item in messages) {
          if (item is! Map) continue;
          final conversationId = backupImportString(item['conversationId']);
          final id = backupImportString(item['id']);
          final createdAt = backupImportDateTime(item['createdAt']);
          if (conversationId == null || id == null || createdAt == null) {
            continue;
          }
          final convQuery = convBox
              .query(ConversationEntity_.id.equals(conversationId))
              .build();
          final convEntity = convQuery.findFirst();
          convQuery.close();
          if (convEntity == null) continue;

          final message = Message(
            id: id,
            conversationId: conversationId,
            role: MessageRole.values.byName(item['role'] as String? ?? 'user'),
            content: item['content'] as String? ?? '',
            createdAt: createdAt,
            status: MessageStatus.values.byName(
              item['status'] as String? ?? 'complete',
            ),
            modelId: item['modelId'] as String?,
            tokenCount: item['tokenCount'] as int?,
            errorMessage: item['errorMessage'] as String?,
            attachmentPaths: _sanitizedAttachmentPaths(
              item['attachmentPaths'],
              attachmentsDir,
            ),
            generationTimeMs: item['generationTimeMs'] as int?,
            reasoningContent: item['reasoningContent'] as String?,
            toolCallId: item['toolCallId'] as String?,
            isProcessing: item['isProcessing'] as bool? ?? false,
            toolSessionId: item['toolSessionId'] as String?,
            variantGroupId: item['variantGroupId'] as String?,
            variantIndex: item['variantIndex'] as int? ?? 0,
            threadOrder: item['threadOrder'] as int? ?? 0,
            isActiveVariant: item['isActiveVariant'] as bool? ?? true,
            parentMessageId: item['parentMessageId'] as String?,
          );

          final entity = MessageEntity.fromDomain(message)
            ..conversation.target = convEntity;
          final query = messageBox.query(MessageEntity_.id.equals(message.id)).build();
          final existing = query.findFirst();
          query.close();
          if (existing != null) entity.internalId = existing.internalId;
          messageBox.put(entity);
        }
      }
    }, (decoded, attachmentsDir));
  }

  List<String>? _sanitizedAttachmentPaths(dynamic raw, String attachmentsDir) {
    if (raw is! List) return null;
    final sanitized = <String>[];
    for (final entry in raw) {
      if (entry is! String || entry.isEmpty) continue;
      final normalized = p.normalize(entry);
      if (normalized == attachmentsDir || p.isWithin(attachmentsDir, normalized)) {
        sanitized.add(entry);
      }
    }
    return sanitized.isEmpty ? null : sanitized;
  }

  Future<void> importZip(Store store, List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (file.isFile) {
        await importFromJson(store, utf8.decode(file.content as List<int>));
      }
    }
  }
}
