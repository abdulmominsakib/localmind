import 'package:localmind/features/chat/data/mcp_server_manager.dart';

import 'tool_definition.dart';
import 'tool_registry.dart';

class McpToolProvider implements ToolProvider {
  final McpServerManager serverManager;

  McpToolProvider({required this.serverManager});

  @override
  Future<List<ToolDefinition>> listTools() async {
    final tools = <ToolDefinition>[];
    for (final label in serverManager.serverLabels) {
      final serverTools = serverManager.getTools(label);
      for (final tool in serverTools) {
        tools.add(
          ToolDefinition(
            name: tool.name,
            description: tool.description ?? '',
            inputSchema: tool.inputSchema,
            providerType: ToolProviderType.mcp,
            providerRef: label,
          ),
        );
      }
    }
    return tools;
  }

  @override
  Future<ToolExecutionResult> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    for (final label in serverManager.serverLabels) {
      final serverTools = serverManager.getTools(label);
      if (serverTools.any((t) => t.name == name)) {
        try {
          final result = await serverManager.callTool(label, name, args);
          return ToolExecutionResult.success(result);
        } catch (e) {
          return ToolExecutionResult.failure(e.toString());
        }
      }
    }
    return const ToolExecutionResult.failure('MCP tool not found');
  }
}
