import 'dart:convert';

import 'tool_definition.dart';
import 'tool_registry.dart';
import 'calendar_service.dart';

class BuiltInToolProvider implements ToolProvider {
  final bool calendarToolsEnabled;

  BuiltInToolProvider({this.calendarToolsEnabled = false});

  @override
  Future<List<ToolDefinition>> listTools() async {
    final tools = <ToolDefinition>[
      const ToolDefinition(
        name: 'calc.add',
        description: 'Add two numbers',
        inputSchema: {
          'type': 'object',
          'properties': {
            'a': {'type': 'number'},
            'b': {'type': 'number'},
          },
          'required': ['a', 'b'],
        },
        providerType: ToolProviderType.builtIn,
      ),
      const ToolDefinition(
        name: 'calc.multiply',
        description: 'Multiply two numbers',
        inputSchema: {
          'type': 'object',
          'properties': {
            'a': {'type': 'number'},
            'b': {'type': 'number'},
          },
          'required': ['a', 'b'],
        },
        providerType: ToolProviderType.builtIn,
      ),
    ];

    if (calendarToolsEnabled) {
      tools.addAll(const [
        ToolDefinition(
          name: 'calendar.list_events',
          description:
              'List upcoming calendar events from the user\'s device calendar. '
              'Returns events with title, start/end time, location, and description. '
              'If no dates are provided, returns events for the next 7 days.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'start_date': {
                'type': 'string',
                'description':
                    'Start date in ISO 8601 format (e.g. 2025-01-15T09:00:00). '
                    'Defaults to today.',
              },
              'end_date': {
                'type': 'string',
                'description':
                    'End date in ISO 8601 format (e.g. 2025-01-22T23:59:59). '
                    'Defaults to 7 days from start.',
              },
            },
          },
          providerType: ToolProviderType.builtIn,
        ),
        ToolDefinition(
          name: 'calendar.create_event',
          description:
              'Create a new event on the user\'s device calendar. '
              'Returns the event ID on success.',
          inputSchema: {
            'type': 'object',
            'properties': {
              'title': {'type': 'string', 'description': 'Event title / name.'},
              'start_date': {
                'type': 'string',
                'description':
                    'Event start date/time in ISO 8601 format (e.g. 2025-01-15T14:00:00).',
              },
              'end_date': {
                'type': 'string',
                'description':
                    'Event end date/time in ISO 8601 format (e.g. 2025-01-15T15:00:00).',
              },
              'description': {
                'type': 'string',
                'description': 'Optional event description / notes.',
              },
              'location': {
                'type': 'string',
                'description': 'Optional event location.',
              },
              'calendar_id': {
                'type': 'string',
                'description':
                    'Optional calendar ID to create the event in. '
                    'Use calendar.list_calendars to see available calendars. '
                    'If omitted, the device default calendar is used.',
              },
            },
            'required': ['title', 'start_date', 'end_date'],
          },
          providerType: ToolProviderType.builtIn,
        ),
        ToolDefinition(
          name: 'calendar.list_calendars',
          description:
              'List all calendars available on the user\'s device. '
              'Returns calendar ID, name, account, and read-only status. '
              'Use this to find the right calendar_id for creating events.',
          inputSchema: {'type': 'object', 'properties': {}},
          providerType: ToolProviderType.builtIn,
        ),
      ]);
    }

    return tools;
  }

  @override
  Future<ToolExecutionResult> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    switch (name) {
      case 'calc.add':
        final sum = (args['a'] as num) + (args['b'] as num);
        return ToolExecutionResult.success(sum.toString());
      case 'calc.multiply':
        final product = (args['a'] as num) * (args['b'] as num);
        return ToolExecutionResult.success(product.toString());

      // -- Calendar tools --
      case 'calendar.list_events':
        return _listEvents(args);
      case 'calendar.create_event':
        return _createEvent(args);
      case 'calendar.list_calendars':
        return _listCalendars();

      default:
        return const ToolExecutionResult.failure('Unknown built-in tool');
    }
  }

  // ---------------------------------------------------------------------------
  // Calendar tool implementations
  // ---------------------------------------------------------------------------

  Future<ToolExecutionResult> _listEvents(Map<String, dynamic> args) async {
    try {
      final cal = CalendarService.instance;
      if (!await cal.hasAccess()) {
        return const ToolExecutionResult.failure(
          'Calendar permission not granted. '
          'Please enable Calendar Access in Settings.',
        );
      }

      DateTime? start;
      DateTime? end;
      if (args['start_date'] is String) {
        start = DateTime.tryParse(args['start_date'] as String);
      }
      if (args['end_date'] is String) {
        end = DateTime.tryParse(args['end_date'] as String);
      }

      final events = await cal.listEvents(start: start, end: end);
      if (events.isEmpty) {
        return ToolExecutionResult.success(
          'No events found in the specified date range.',
        );
      }
      return ToolExecutionResult.success(
        const JsonEncoder.withIndent('  ').convert(events),
      );
    } catch (e) {
      return ToolExecutionResult.failure('Failed to list events: $e');
    }
  }

  Future<ToolExecutionResult> _createEvent(Map<String, dynamic> args) async {
    try {
      final cal = CalendarService.instance;
      if (!await cal.hasAccess()) {
        return const ToolExecutionResult.failure(
          'Calendar permission not granted. '
          'Please enable Calendar Access in Settings.',
        );
      }

      final title = args['title'] as String?;
      final startStr = args['start_date'] as String?;
      final endStr = args['end_date'] as String?;

      if (title == null || startStr == null || endStr == null) {
        return const ToolExecutionResult.failure(
          'title, start_date, and end_date are required.',
        );
      }

      final startDate = DateTime.tryParse(startStr);
      final endDate = DateTime.tryParse(endStr);
      if (startDate == null || endDate == null) {
        return const ToolExecutionResult.failure(
          'Invalid date format. Use ISO 8601 (e.g. 2025-01-15T14:00:00).',
        );
      }

      final result = await cal.createEvent(
        title: title,
        startDate: startDate,
        endDate: endDate,
        description: args['description'] as String?,
        location: args['location'] as String?,
        calendarId: args['calendar_id'] as String?,
      );
      return ToolExecutionResult.success(
        const JsonEncoder.withIndent('  ').convert(result),
      );
    } catch (e) {
      return ToolExecutionResult.failure('Failed to create event: $e');
    }
  }

  Future<ToolExecutionResult> _listCalendars() async {
    try {
      final cal = CalendarService.instance;
      if (!await cal.hasAccess()) {
        return const ToolExecutionResult.failure(
          'Calendar permission not granted. '
          'Please enable Calendar Access in Settings.',
        );
      }

      final calendars = await cal.listCalendars();
      if (calendars.isEmpty) {
        return ToolExecutionResult.success('No calendars found on device.');
      }
      return ToolExecutionResult.success(
        const JsonEncoder.withIndent('  ').convert(calendars),
      );
    } catch (e) {
      return ToolExecutionResult.failure('Failed to list calendars: $e');
    }
  }
}
