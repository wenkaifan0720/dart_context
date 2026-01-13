import 'dart:async';

/// Represents a tool that the LLM can call.
class LlmTool {
  const LlmTool({
    required this.name,
    required this.description,
    required this.parameters,
    this.required = const [],
  });

  final String name;
  final String description;
  final Map<String, LlmToolParameter> parameters;
  final List<String> required;

  Map<String, dynamic> toAnthropicSchema() => {
        'name': name,
        'description': description,
        'input_schema': {
          'type': 'object',
          'properties': {
            for (final entry in parameters.entries)
              entry.key: entry.value.toSchema(),
          },
          if (required.isNotEmpty) 'required': required,
        },
      };
}

/// A tool parameter definition.
class LlmToolParameter {
  const LlmToolParameter({
    required this.type,
    required this.description,
    this.enumValues,
  });

  final String type;
  final String description;
  final List<String>? enumValues;

  Map<String, dynamic> toSchema() => {
        'type': type,
        'description': description,
        if (enumValues != null) 'enum': enumValues,
      };
}

/// A tool call request from the LLM.
class LlmToolCall {
  const LlmToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// Result of a tool call.
class LlmToolResult {
  const LlmToolResult({
    required this.toolCallId,
    required this.content,
    this.isError = false,
  });

  final String toolCallId;
  final String content;
  final bool isError;
}

/// A message in the conversation.
sealed class LlmMessage {
  const LlmMessage();
}

/// System message.
class SystemMessage extends LlmMessage {
  const SystemMessage(this.content);
  final String content;
}

/// User message.
class UserMessage extends LlmMessage {
  const UserMessage(this.content);
  final String content;
}

/// Assistant message with optional tool calls.
class AssistantMessage extends LlmMessage {
  const AssistantMessage({
    this.content,
    this.toolCalls = const [],
  });

  final String? content;
  final List<LlmToolCall> toolCalls;
}

/// Tool results message.
class ToolResultsMessage extends LlmMessage {
  const ToolResultsMessage(this.results);
  final List<LlmToolResult> results;
}

/// Response from the LLM.
class LlmResponse {
  const LlmResponse({
    this.content,
    this.toolCalls = const [],
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  final String? content;
  final List<LlmToolCall> toolCalls;
  final int inputTokens;
  final int outputTokens;

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Configuration for the LLM service.
class LlmConfig {
  const LlmConfig({
    required this.model,
    this.temperature = 1.0,
    this.maxTokens = 4096,
  });

  final String model;
  final double temperature;
  final int maxTokens;

  /// Model for folder-level docs (cheaper).
  static const folderLevel = LlmConfig(
    model: 'claude-sonnet-4-20250514',
    maxTokens: 4096,
  );

  /// Model for module-level docs (mid-tier).
  static const moduleLevel = LlmConfig(
    model: 'claude-sonnet-4-20250514',
    maxTokens: 8192,
  );

  /// Model for project-level docs (premium).
  static const projectLevel = LlmConfig(
    model: 'claude-sonnet-4-20250514',
    maxTokens: 16384,
  );
}

/// Abstract LLM service interface.
abstract class LlmService {
  /// Send a message to the LLM and get a response.
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required LlmConfig config,
    List<LlmTool> tools = const [],
  });

  /// Get the current token usage.
  (int input, int output) get tokenUsage;
}
