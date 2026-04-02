import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:localmind/features/conversations/data/models/conversation.dart';
import 'package:localmind/features/personas/data/models/persona.dart';
import '../storage/hive_initializer.dart';

final hiveBoxesProvider = Provider<HiveBoxes>((ref) {
  throw UnimplementedError('Must be overridden in main.dart');
});

final settingsBoxProvider = Provider<dynamic>((ref) {
  final boxes = ref.watch(hiveBoxesProvider);
  return boxes.settings;
});

final conversationsBoxProvider = Provider<Box<Conversation>>((ref) {
  final boxes = ref.watch(hiveBoxesProvider);
  return boxes.conversations;
});

final conversationsProvider = Provider<List<Conversation>>((ref) {
  final box = ref.watch(conversationsBoxProvider);
  final conversations = box.values.toList();
  conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return conversations;
});

final recentConversationsProvider = Provider<List<Conversation>>((ref) {
  final all = ref.watch(conversationsProvider);
  return all.take(3).toList();
});

final personasBoxProvider = Provider<Box<Persona>>((ref) {
  final boxes = ref.watch(hiveBoxesProvider);
  return boxes.personas;
});

final personasProvider = Provider<List<Persona>>((ref) {
  final box = ref.watch(personasBoxProvider);
  return box.values.toList();
});
