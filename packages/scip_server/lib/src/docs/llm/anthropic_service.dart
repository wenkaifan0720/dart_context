import 'dart:convert';
import 'package:http/http.dart' as http;

import 'llm_service.dart';

/// Anthropic Claude implementation of LlmService.
class AnthropicService implements LlmService {
  AnthropicService({
    required String apiKey,
    http.Client? client,
  })  : _apiKey = apiKey,
        _client = client ?? http.Client();

  final String _apiKey;
  final http.Client _client;
  int _totalInputTokens = 0;
  int _totalOutputTokens = 0;

  static const _apiUrl = 'https://api.anthropic.com/v1/messages';
  static const _apiVersion = '2023-06-01';

  @override
  (int input, int output) get tokenUsage => (_totalInputTokens, _totalOutputTokens);

  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required LlmConfig config,
    List<LlmTool> tools = const [],
  }) async {
    // Extract system message
    String? systemPrompt;
    final conversationMessages = <Map<String, dynamic>>[];

    for (final message in messages) {
      switch (message) {
        case SystemMessage(:final content):
          systemPrompt = content;
        case UserMessage(:final content):
          conversationMessages.add({
            'role': 'user',
            'content': content,
          });
        case AssistantMessage(:final content, :final toolCalls):
          final contentList = <Map<String, dynamic>>[];
          if (content != null && content.isNotEmpty) {
            contentList.add({'type': 'text', 'text': content});
          }
          for (final call in toolCalls) {
            contentList.add({
              'type': 'tool_use',
              'id': call.id,
              'name': call.name,
              'input': call.arguments,
            });
          }
          if (contentList.isNotEmpty) {
            conversationMessages.add({
              'role': 'assistant',
              'content': contentList,
            });
          }
        case ToolResultsMessage(:final results):
          final contentList = <Map<String, dynamic>>[];
          for (final result in results) {
            contentList.add({
              'type': 'tool_result',
              'tool_use_id': result.toolCallId,
              'content': result.content,
              if (result.isError) 'is_error': true,
            });
          }
          conversationMessages.add({
            'role': 'user',
            'content': contentList,
          });
      }
    }

    final body = <String, dynamic>{
      'model': config.model,
      'max_tokens': config.maxTokens,
      'temperature': config.temperature,
      'messages': conversationMessages,
    };

    if (systemPrompt != null) {
      body['system'] = systemPrompt;
    }

    if (tools.isNotEmpty) {
      body['tools'] = tools.map((t) => t.toAnthropicSchema()).toList();
    }

    final response = await _client.post(
      Uri.parse(_apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': _apiKey,
        'anthropic-version': _apiVersion,
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw LlmException(
        'Anthropic API error: ${response.statusCode} - ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseResponse(json);
  }

  LlmResponse _parseResponse(Map<String, dynamic> json) {
    // Extract token usage
    final usage = json['usage'] as Map<String, dynamic>?;
    final inputTokens = usage?['input_tokens'] as int? ?? 0;
    final outputTokens = usage?['output_tokens'] as int? ?? 0;
    _totalInputTokens += inputTokens;
    _totalOutputTokens += outputTokens;

    // Parse content
    final content = json['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      return LlmResponse(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
      );
    }

    String? textContent;
    final toolCalls = <LlmToolCall>[];

    for (final block in content) {
      final blockMap = block as Map<String, dynamic>;
      final type = blockMap['type'] as String?;

      switch (type) {
        case 'text':
          textContent = blockMap['text'] as String?;
        case 'tool_use':
          toolCalls.add(LlmToolCall(
            id: blockMap['id'] as String,
            name: blockMap['name'] as String,
            arguments: blockMap['input'] as Map<String, dynamic>,
          ));
      }
    }

    return LlmResponse(
      content: textContent,
      toolCalls: toolCalls,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
    );
  }
}

/// Exception thrown by LLM service.
class LlmException implements Exception {
  const LlmException(this.message);
  final String message;

  @override
  String toString() => 'LlmException: $message';
}
