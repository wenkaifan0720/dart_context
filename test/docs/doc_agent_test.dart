import 'dart:async';

import 'package:scip_server/src/docs/context_builder.dart';
import 'package:scip_server/src/docs/context_extractor.dart';
import 'package:scip_server/src/docs/llm/doc_agent.dart';
import 'package:scip_server/src/docs/llm/doc_tools.dart';
import 'package:scip_server/src/docs/llm/llm_service.dart';
import 'package:scip_server/src/docs/llm_interface.dart';
import 'package:scip_server/src/index/scip_index.dart';
import 'package:test/test.dart';

/// Mock LLM service for testing.
class MockLlmService implements LlmService {
  final List<List<LlmMessage>> sentMessages = [];
  final List<LlmResponse> responses = [];
  int _responseIndex = 0;
  int _inputTokens = 0;
  int _outputTokens = 0;

  void addResponse(LlmResponse response) {
    responses.add(response);
  }

  void addTextResponse(String text) {
    responses.add(LlmResponse(
      content: text,
      inputTokens: 100,
      outputTokens: 50,
    ));
  }

  void addToolCallResponse(List<LlmToolCall> calls) {
    responses.add(LlmResponse(
      toolCalls: calls,
      inputTokens: 100,
      outputTokens: 50,
    ));
  }

  @override
  Future<LlmResponse> chat({
    required List<LlmMessage> messages,
    required LlmConfig config,
    List<LlmTool> tools = const [],
  }) async {
    sentMessages.add(List.from(messages));

    if (_responseIndex >= responses.length) {
      return const LlmResponse(content: 'Default response');
    }

    final response = responses[_responseIndex++];
    _inputTokens += response.inputTokens;
    _outputTokens += response.outputTokens;
    return response;
  }

  @override
  (int input, int output) get tokenUsage => (_inputTokens, _outputTokens);
}

/// Mock tool registry that tracks calls.
class MockToolRegistry extends DocToolRegistry {
  final Map<String, List<Map<String, dynamic>>> toolCalls = {};
  final Map<String, String> toolResults = {};

  MockToolRegistry() : super(
    projectRoot: '/mock/project',
    scipIndex: ScipIndex.empty(projectRoot: '/mock/project'),
    docsPath: '/mock/project/.dart_context/docs',
  );

  void setToolResult(String name, String result) {
    toolResults[name] = result;
  }

  @override
  Future<String> executeTool(String name, Map<String, dynamic> args) async {
    toolCalls.putIfAbsent(name, () => []).add(args);
    return toolResults[name] ?? 'Mock result for $name';
  }
}

void main() {
  group('DocGenerationAgent', () {
    late MockLlmService mockLlm;
    late MockToolRegistry mockTools;
    late DocGenerationAgent agent;

    setUp(() {
      mockLlm = MockLlmService();
      mockTools = MockToolRegistry();
      agent = DocGenerationAgent(
        llmService: mockLlm,
        toolRegistry: mockTools,
        maxIterations: 5,
      );
    });

    DocContext createTestContext() {
      return DocContext(
        current: FolderContext(
          path: 'lib/features/auth',
          files: [
            FileContext(
              path: 'lib/features/auth/auth_service.dart',
              docComments: ['Authentication service'],
              publicApi: [
                ApiSignature(
                  name: 'AuthService',
                  kind: 'class',
                  signature: 'class AuthService',
                ),
                ApiSignature(
                  name: 'login',
                  kind: 'method',
                  signature: 'Future<User> login(String email, String password)',
                ),
              ],
              symbols: [],
            ),
          ],
          internalDeps: {},
          externalDeps: {},
          usedSymbols: {},
        ),
        internalDeps: [],
        externalDeps: [],
        dependents: [],
      );
    }

    test('generates doc with no tool calls', () async {
      mockLlm.addTextResponse('''
# Auth

Authentication module for user login.

## Overview

This folder contains the AuthService class for handling user authentication.

## Key Components

- [AuthService](scip://lib/features/auth/auth_service.dart/AuthService#)
''');

      final result = await agent.generateFolderDoc(createTestContext());

      expect(result.content, contains('# Auth'));
      expect(result.content, contains('AuthService'));
      expect(result.smartSymbols, contains('scip://lib/features/auth/auth_service.dart/AuthService#'));
    });

    test('handles tool calls correctly', () async {
      // First response requests a tool call
      mockLlm.addToolCallResponse([
        LlmToolCall(
          id: 'call_1',
          name: 'list_folder',
          arguments: {'path': 'lib/features/auth'},
        ),
      ]);

      mockTools.setToolResult('list_folder', '''
Contents of lib/features/auth:
- auth_service.dart
- auth_repository.dart
''');

      // Second response generates final doc
      mockLlm.addTextResponse('''
# Auth

This folder contains authentication services.
''');

      final result = await agent.generateFolderDoc(createTestContext());

      // Verify tool was called
      expect(mockTools.toolCalls['list_folder'], isNotNull);
      expect(mockTools.toolCalls['list_folder']!.length, equals(1));

      // Verify final doc generated
      expect(result.content, contains('# Auth'));
    });

    test('respects max iterations', () async {
      // Add tool call responses up to max iterations
      for (var i = 0; i < 5; i++) {
        mockLlm.addToolCallResponse([
          LlmToolCall(
            id: 'call_$i',
            name: 'list_folder',
            arguments: {'path': 'lib'},
          ),
        ]);
      }

      // Response for the forced final generation (after max iterations)
      mockLlm.addTextResponse('# Generated After Max Iterations');

      final result = await agent.generateFolderDoc(createTestContext());

      // Should have stopped at maxIterations and generated
      // Verify that it didn't get stuck in an infinite loop
      expect(mockLlm.sentMessages.length, lessThanOrEqualTo(7));
      // The agent should return some content
      expect(result.content, contains('Generated After Max Iterations'));
    });

    test('extracts smart symbols from content', () async {
      mockLlm.addTextResponse('''
# Test

Links to [AuthService](scip://lib/auth.dart/AuthService#) and 
[login](scip://lib/auth.dart/AuthService#login).
''');

      final result = await agent.generateFolderDoc(createTestContext());

      expect(result.smartSymbols, contains('scip://lib/auth.dart/AuthService#'));
      // The regex extracts up to the closing paren of the markdown link
      expect(result.smartSymbols.any((s) => s.contains('login')), isTrue);
    });

    test('extracts title from markdown', () async {
      mockLlm.addTextResponse('''
# My Feature

Some content here.
''');

      final result = await agent.generateFolderDoc(createTestContext());

      expect(result.title, equals('My Feature'));
    });

    test('extracts summary from first paragraph', () async {
      mockLlm.addTextResponse('''
# Feature

This is the first paragraph which serves as the summary.
It spans multiple lines but should be captured.

## Second Section

More content here.
''');

      final result = await agent.generateFolderDoc(createTestContext());

      expect(result.summary, contains('first paragraph'));
    });

    test('tracks token usage', () async {
      mockLlm.addToolCallResponse([
        LlmToolCall(id: '1', name: 'list_folder', arguments: {}),
      ]);
      mockLlm.addTextResponse('# Doc');

      await agent.generateFolderDoc(createTestContext());

      final (input, output) = agent.tokenUsage;
      expect(input, greaterThan(0));
      expect(output, greaterThan(0));
    });

    test('generateModuleDoc combines folder summaries', () async {
      mockLlm.addTextResponse('''
# Module

Overview of the module.

## Components

- Auth
- Users
''');

      final folders = [
        FolderDocSummary(
          path: 'lib/features/auth',
          content: '# Auth\n\nAuth content',
          summary: 'Authentication module',
          smartSymbols: ['scip://auth/AuthService#'],
        ),
        FolderDocSummary(
          path: 'lib/features/users',
          content: '# Users\n\nUsers content',
          summary: 'User management',
          smartSymbols: ['scip://users/UserService#'],
        ),
      ];

      final result = await agent.generateModuleDoc('features', folders);

      expect(result.title, equals('features Module'));
      // Should include smart symbols from folders
      expect(result.smartSymbols, contains('scip://auth/AuthService#'));
      expect(result.smartSymbols, contains('scip://users/UserService#'));
    });

    test('generateProjectDoc combines module summaries', () async {
      mockLlm.addTextResponse('''
# MyProject

Project overview.
''');

      final modules = [
        ModuleDocSummary(
          name: 'core',
          content: '# Core',
          summary: 'Core utilities',
          smartSymbols: ['scip://core/Utils#'],
        ),
        ModuleDocSummary(
          name: 'features',
          content: '# Features',
          summary: 'App features',
          smartSymbols: ['scip://features/Feature#'],
        ),
      ];

      final result = await agent.generateProjectDoc('MyProject', modules);

      expect(result.title, equals('MyProject'));
      expect(result.smartSymbols, contains('scip://core/Utils#'));
      expect(result.smartSymbols, contains('scip://features/Feature#'));
    });
  });
}
