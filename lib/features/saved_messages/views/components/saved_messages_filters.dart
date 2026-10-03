import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/l10n/app_localizations.dart';
import '../../providers/saved_message_providers.dart';

/// The label and icon each saved-message filter shows in the menu and in
/// the active-filter chip.
extension SavedMessageListFilterDisplay on SavedMessageListFilter {
  String label(AppLocalizations l10n) => switch (this) {
    SavedMessageListFilter.all => l10n.all_chats,
    SavedMessageListFilter.tempChats => l10n.filter_temp_chats,
    SavedMessageListFilter.user => l10n.filter_user_messages,
    SavedMessageListFilter.assistant => l10n.filter_assistant_messages,
    SavedMessageListFilter.archived => l10n.filter_archived,
  };

  List<List<dynamic>> get icon => switch (this) {
    SavedMessageListFilter.all => HugeIcons.strokeRoundedBookmark01,
    SavedMessageListFilter.tempChats => HugeIcons.strokeRoundedIncognito,
    SavedMessageListFilter.user => HugeIcons.strokeRoundedUser,
    SavedMessageListFilter.assistant => HugeIcons.strokeRoundedSparkles,
    SavedMessageListFilter.archived => HugeIcons.strokeRoundedArchive,
  };
}
