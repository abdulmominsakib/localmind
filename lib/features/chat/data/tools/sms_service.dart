import 'dart:io';

import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper around [SmsQuery] + [Permission.sms] for the built-in
/// SMS tools.
///
/// All methods return plain Dart types (strings / maps) so tool results can
/// be serialised without leaking platform model classes into the tool layer.
///
/// SMS is queried on demand only (no background listening, no caching,
/// no persistence). Bodies are returned only on explicit query; callers
/// should keep `count` small and prefer `address` filters.
///
/// Android-only: iOS has no public SMS-read API, so every method throws
/// [UnsupportedError] on iOS.
class SmsService {
  SmsService._();
  static final instance = SmsService._();

  final SmsQuery _query = SmsQuery();

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Request SMS read access. Returns `true` when granted.
  ///
  /// Returns `false` on iOS (unsupported) without prompting.
  Future<bool> requestAccess() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.sms.status;
    if (status.isGranted) return true;
    final result = await Permission.sms.request();
    return result.isGranted;
  }

  /// Check current permission status without prompting.
  Future<bool> hasAccess() async {
    if (!Platform.isAndroid) return false;
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  // ---------------------------------------------------------------------------
  // SMS — read
  // ---------------------------------------------------------------------------

  /// Queries recent SMS messages, newest first when [sort] is true.
  ///
  /// [count] is clamped to 1..50 (defaults to 20). Pass [address] to
  /// restrict to a single sender/recipient, [query] for a case-insensitive
  /// substring match against address/body, and [includeBody] to omit bodies
  /// (metadata only).
  ///
  /// Throws [UnsupportedError] on non-Android platforms and [StateError]
  /// when SMS permission is missing.
  Future<List<Map<String, dynamic>>> queryMessages({
    String? address,
    int count = 20,
    String? query,
    bool includeBody = true,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'SMS reading is only supported on Android. '
        'iOS does not expose an SMS-read API.',
      );
    }
    if (!await hasAccess()) {
      throw StateError(
        'SMS permission not granted. '
        'Please enable SMS Access in Settings.',
      );
    }

    final safeCount = count.clamp(1, 50);
    final trimmedAddress = address?.trim();
    final normalizedQuery = query?.trim().toLowerCase();

    final messages = await _query.querySms(
      address: (trimmedAddress == null || trimmedAddress.isEmpty)
          ? null
          : trimmedAddress,
      count: safeCount,
      kinds: const [SmsQueryKind.inbox, SmsQueryKind.sent],
      sort: true,
    );

    final filtered = normalizedQuery == null || normalizedQuery.isEmpty
        ? messages
        : messages
              .where((m) {
                final haystack = '${m.address ?? ''} ${m.body ?? ''}'
                    .toLowerCase();
                return haystack.contains(normalizedQuery);
              })
              .toList(growable: false);

    return filtered
        .take(safeCount)
        .map(
          (m) => {
            'id': m.id,
            'address': m.address,
            'date': m.date?.toIso8601String(),
            'date_sent': m.dateSent?.toIso8601String(),
            'kind': m.kind?.name,
            'thread_id': m.threadId,
            'is_read': m.isRead,
            if (includeBody) 'body': m.body,
          },
        )
        .toList(growable: false);
  }
}
