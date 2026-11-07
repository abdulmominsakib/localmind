/// Role of a message sender in a chat conversation.
enum LlamaChatRole {
  /// System instruction or context.
  system,

  /// Human user input.
  user,

  /// AI model response.
  assistant,

  /// Tool or function call output.
  tool,
}
