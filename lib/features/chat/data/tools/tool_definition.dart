enum ToolProviderType { builtIn, mcp, lmStudioServer }

class ToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final ToolProviderType providerType;
  final String? providerRef;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.providerType,
    this.providerRef,
  });
}

class ToolExecutionResult {
  final bool success;
  final String output;
  final String? error;

  const ToolExecutionResult.success(this.output) : success = true, error = null;

  const ToolExecutionResult.failure(this.error) : success = false, output = '';
}
