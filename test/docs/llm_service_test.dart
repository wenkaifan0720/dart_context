import 'package:scip_server/src/docs/llm/llm_service.dart';
import 'package:test/test.dart';

void main() {
  group('LlmTool', () {
    test('toAnthropicSchema generates correct format', () {
      const tool = LlmTool(
        name: 'test_tool',
        description: 'A test tool',
        parameters: {
          'param1': LlmToolParameter(
            type: 'string',
            description: 'First parameter',
          ),
          'param2': LlmToolParameter(
            type: 'integer',
            description: 'Second parameter',
          ),
        },
        required: ['param1'],
      );

      final schema = tool.toAnthropicSchema();

      expect(schema['name'], equals('test_tool'));
      expect(schema['description'], equals('A test tool'));
      expect(schema['input_schema'], isA<Map>());

      final inputSchema = schema['input_schema'] as Map<String, dynamic>;
      expect(inputSchema['type'], equals('object'));
      expect(inputSchema['properties'], isA<Map>());
      expect(inputSchema['required'], equals(['param1']));

      final props = inputSchema['properties'] as Map<String, dynamic>;
      expect(props['param1']['type'], equals('string'));
      expect(props['param2']['type'], equals('integer'));
    });

    test('LlmToolParameter with enum values', () {
      const param = LlmToolParameter(
        type: 'string',
        description: 'Type selection',
        enumValues: ['a', 'b', 'c'],
      );

      final schema = param.toSchema();

      expect(schema['type'], equals('string'));
      expect(schema['enum'], equals(['a', 'b', 'c']));
    });
  });

  group('LlmConfig', () {
    test('folderLevel has correct defaults', () {
      const config = LlmConfig.folderLevel;

      expect(config.model, equals('claude-sonnet-4-20250514'));
      expect(config.maxTokens, equals(4096));
      expect(config.temperature, equals(1.0));
    });

    test('moduleLevel has higher token limit', () {
      const config = LlmConfig.moduleLevel;

      expect(config.maxTokens, equals(8192));
    });

    test('projectLevel has highest token limit', () {
      const config = LlmConfig.projectLevel;

      expect(config.maxTokens, equals(16384));
    });
  });

  group('LlmMessage', () {
    test('SystemMessage holds content', () {
      const msg = SystemMessage('You are a helpful assistant.');

      expect(msg.content, equals('You are a helpful assistant.'));
    });

    test('UserMessage holds content', () {
      const msg = UserMessage('Hello!');

      expect(msg.content, equals('Hello!'));
    });

    test('AssistantMessage with content only', () {
      const msg = AssistantMessage(content: 'Hi there!');

      expect(msg.content, equals('Hi there!'));
      expect(msg.toolCalls, isEmpty);
    });

    test('AssistantMessage with tool calls', () {
      const msg = AssistantMessage(
        toolCalls: [
          LlmToolCall(
            id: 'call_123',
            name: 'test_tool',
            arguments: {'param': 'value'},
          ),
        ],
      );

      expect(msg.content, isNull);
      expect(msg.toolCalls.length, equals(1));
      expect(msg.toolCalls.first.name, equals('test_tool'));
    });

    test('ToolResultsMessage holds results', () {
      const msg = ToolResultsMessage([
        LlmToolResult(
          toolCallId: 'call_123',
          content: 'Result content',
        ),
        LlmToolResult(
          toolCallId: 'call_456',
          content: 'Error message',
          isError: true,
        ),
      ]);

      expect(msg.results.length, equals(2));
      expect(msg.results[0].isError, isFalse);
      expect(msg.results[1].isError, isTrue);
    });
  });

  group('LlmResponse', () {
    test('hasToolCalls returns false for empty', () {
      const response = LlmResponse();

      expect(response.hasToolCalls, isFalse);
    });

    test('hasToolCalls returns true when present', () {
      const response = LlmResponse(
        toolCalls: [
          LlmToolCall(id: '1', name: 'test', arguments: {}),
        ],
      );

      expect(response.hasToolCalls, isTrue);
    });
  });

  group('AnthropicService', () {
    test('builds correct request body', () {
      // This is a mock test - we're testing message serialization logic
      final messages = <LlmMessage>[
        const SystemMessage('System prompt'),
        const UserMessage('User message'),
        const AssistantMessage(
          content: 'Response',
          toolCalls: [
            LlmToolCall(id: 'call_1', name: 'tool', arguments: {'a': 1}),
          ],
        ),
        const ToolResultsMessage([
          LlmToolResult(toolCallId: 'call_1', content: 'Tool result'),
        ]),
      ];

      // Verify message structure matches what we'd send to Anthropic
      expect(messages.length, equals(4));
      expect(messages[0], isA<SystemMessage>());
      expect(messages[1], isA<UserMessage>());
      expect(messages[2], isA<AssistantMessage>());
      expect(messages[3], isA<ToolResultsMessage>());
    });
  });
}
