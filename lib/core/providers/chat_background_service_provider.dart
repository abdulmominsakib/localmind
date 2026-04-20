import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/chat_background_service.dart';

final chatBackgroundServiceProvider = Provider<ChatBackgroundService>((ref) {
  return ChatBackgroundService();
});
