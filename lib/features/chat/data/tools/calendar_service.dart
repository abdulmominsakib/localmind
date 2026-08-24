import 'package:device_calendar_plus/device_calendar_plus.dart';

/// Thin wrapper around [DeviceCalendar] for the built-in calendar tools.
///
/// All methods return plain Dart types (strings / maps) so tool results can be
/// serialised without leaking platform model classes into the tool layer.
class CalendarService {
  CalendarService._();
  static final instance = CalendarService._();

  final _plugin = DeviceCalendar.instance;

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  /// Request full calendar access. Returns `true` when granted.
  Future<bool> requestAccess() async {
    final status = await _plugin.requestPermissions();
    return status == CalendarPermissionStatus.granted;
  }

  /// Check current permission status without prompting.
  Future<bool> hasAccess() async {
    final status = await _plugin.hasPermissions();
    return status == CalendarPermissionStatus.granted;
  }

  // ---------------------------------------------------------------------------
  // Calendars
  // ---------------------------------------------------------------------------

  /// Returns a JSON-friendly list of available calendars.
  Future<List<Map<String, dynamic>>> listCalendars() async {
    final calendars = await _plugin.listCalendars();
    return calendars
        .map(
          (c) => {
            'id': c.id,
            'name': c.name,
            'is_read_only': c.readOnly,
            'is_primary': c.isPrimary,
            'account_name': c.accountName,
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Events – read
  // ---------------------------------------------------------------------------

  /// Lists events in [start]..[end]. Both default to "today → +7 days".
  Future<List<Map<String, dynamic>>> listEvents({
    DateTime? start,
    DateTime? end,
  }) async {
    final from = start ?? _todayStart();
    final to = end ?? from.add(const Duration(days: 7));

    final events = await _plugin.listEvents(from, to);
    return events
        .map(
          (e) => {
            'id': e.eventId,
            'title': e.title,
            'start': e.startDate.toIso8601String(),
            'end': e.endDate.toIso8601String(),
            'all_day': e.isAllDay,
            'location': e.location,
            'description': e.description,
            'calendar_id': e.calendarId,
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Events – write
  // ---------------------------------------------------------------------------

  /// Creates a new event and returns a result map with the event ID.
  Future<Map<String, dynamic>> createEvent({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    String? description,
    String? location,
    String? calendarId,
  }) async {
    try {
      final eventId = await _plugin.createEvent(
        title: title,
        startDate: startDate,
        endDate: endDate,
        description: description,
        location: location,
        calendarId: calendarId,
      );

      return {
        'success': true,
        'event_id': eventId,
        'message': 'Event "$title" created successfully.',
      };
    } on DeviceCalendarException catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  DateTime _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}
