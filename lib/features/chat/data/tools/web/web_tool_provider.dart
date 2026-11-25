import 'dart:convert';

import '../tool_definition.dart';
import '../tool_registry.dart';
import 'web_search_client.dart';
import 'web_search_service.dart';

/// `web.search` and `web.fetch`, offered to models that call tools.
class WebToolProvider implements ToolProvider {
  WebToolProvider({required this.service, this.enabled = true});

  final WebSearchService service;
  final bool enabled;

  static const searchTool = 'web.search';
  static const fetchTool = 'web.fetch';

  @override
  Future<List<ToolDefinition>> listTools() async {
    if (!enabled || !await service.isConfigured()) return const [];
    return const [
      ToolDefinition(
        name: searchTool,
        description:
            'Search the web. Returns titles, links and short snippets. Use it '
            'for recent events, facts you are unsure of, or anything the user '
            'asks you to look up. Follow up with web.fetch to read a result.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'query': {'type': 'string', 'description': 'What to search for.'},
            'count': {
              'type': 'integer',
              'description': 'Number of results, 1 to 10. Defaults to 5.',
            },
          },
          'required': ['query'],
        },
        providerType: ToolProviderType.builtIn,
      ),
      ToolDefinition(
        name: fetchTool,
        description:
            'Read a web page and return its main text. Use it on a link from '
            'web.search or one the user gave.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'url': {'type': 'string', 'description': 'An http or https link.'},
          },
          'required': ['url'],
        },
        providerType: ToolProviderType.builtIn,
      ),
    ];
  }

  @override
  Future<ToolExecutionResult> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (name) {
        case searchTool:
          final query = args['query']?.toString() ?? '';
          final count = (args['count'] as num?)?.toInt() ?? 5;
          final results = await service.search(query, count: count);
          if (results.isEmpty) {
            return const ToolExecutionResult.success('No results found.');
          }
          return ToolExecutionResult.success(
            const JsonEncoder.withIndent(
              '  ',
            ).convert([for (final r in results) r.toJson()]),
          );
        case fetchTool:
          final page = await service.fetch(args['url']?.toString() ?? '');
          final title = page.title.isEmpty ? '' : '${page.title}\n';
          final note = page.truncated ? '\n\n[Page text was shortened.]' : '';
          return ToolExecutionResult.success(
            '$title${page.url}\n\n${page.text}$note',
          );
        default:
          return const ToolExecutionResult.failure('Unknown web tool');
      }
    } on WebSearchException catch (e) {
      return ToolExecutionResult.failure(e.message);
    } catch (e) {
      return ToolExecutionResult.failure('Web tool failed: $e');
    }
  }
}
