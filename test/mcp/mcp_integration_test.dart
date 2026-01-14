import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

import 'package:code_context/code_context_mcp.dart';

void main() {
  group('MCP Integration', () {
    late Directory tempDir;
    late TestEnvironment env;

    setUp(() async {
      // Create a temp project with pubspec.yaml
      tempDir = await Directory.systemTemp.createTemp('mcp_integration_test_');
      await File('${tempDir.path}/pubspec.yaml').writeAsString('''
name: test_project
environment:
  sdk: ^3.0.0
''');

      // Create .dart_tool/package_config.json
      await Directory('${tempDir.path}/.dart_tool').create();
      await File('${tempDir.path}/.dart_tool/package_config.json')
          .writeAsString('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "test_project",
      "rootUri": "../",
      "packageUri": "lib/",
      "languageVersion": "3.0"
    }
  ]
}
''');

      // Create lib/ with a simple dart file
      await Directory('${tempDir.path}/lib').create();
      await File('${tempDir.path}/lib/main.dart').writeAsString('''
/// Main entry point.
void main() {
  print('Hello');
}

class MyClass {
  void doSomething() {}
}
''');

      // Create test environment
      env = TestEnvironment(tempDir.path);
      await env.initializeServer();
    });

    tearDown(() async {
      await env.shutdown();
      await tempDir.delete(recursive: true);
    });

    group('Tool Registration', () {
      test('all 5 tools are registered', () async {
        final tools = await env.serverConnection.listTools();
        final toolNames = tools.tools.map((t) => t.name).toSet();

        expect(toolNames, contains('dart_query'));
        expect(toolNames, contains('dart_index_flutter'));
        expect(toolNames, contains('dart_index_deps'));
        expect(toolNames, contains('dart_refresh'));
        expect(toolNames, contains('dart_status'));
      });

      test('dart_query tool has correct schema', () async {
        final tools = await env.serverConnection.listTools();
        final queryTool = tools.tools.firstWhere((t) => t.name == 'dart_query');

        expect(queryTool.description, contains('Query'));
        expect(queryTool.inputSchema, isNotNull);
      });
    });

    group('Tool Responses', () {
      test('dart_status returns valid response', () async {
        final result = await env.callTool('dart_status', {});

        // Should return some content (either indexed info or not indexed)
        expect(result.textContent, contains('Dart Context Status'));
      });

      test('dart_index_flutter fails for missing packages dir', () async {
        // Create a fake flutter dir without packages
        final fakeFlutter = Directory('${tempDir.path}/fake_flutter');
        await fakeFlutter.create();
        await File('${fakeFlutter.path}/version').writeAsString('3.0.0');

        final result = await env.callTool('dart_index_flutter', {
          'flutterRoot': fakeFlutter.path,
        });

        expect(result.isError, isTrue);
        expect(result.textContent, contains('Flutter'));
      });

      test('dart_index_deps fails for missing pubspec.lock', () async {
        final result = await env.callTool('dart_index_deps', {
          'projectRoot': tempDir.path,
        });

        expect(result.isError, isTrue);
        expect(result.textContent, contains('pubspec.lock'));
      });

      test('dart_refresh returns response', () async {
        final result = await env.callTool('dart_refresh', {});

        // Should return something (success or no project found)
        expect(result.textContent.isNotEmpty, isTrue);
      });

      test('dart_query with missing query fails validation', () async {
        final result = await env.callTool('dart_query', {});

        expect(result.isError, isTrue);
        // MCP validates schema before calling handler
        expect(result.textContent, contains('query'));
      });
    });

    group('Error Handling', () {
      test('invalid tool name throws or returns error', () async {
        try {
          final result = await env.callTool('nonexistent_tool', {});
          // If it doesn't throw, should have error content
          expect(result.isError, isTrue);
        } catch (e) {
          // Expected - MCP throws for unknown tools
          expect(e, isNotNull);
        }
      });
    });

    group('Real Query Execution', () {
      // Note: These tests use the default root (set during init) rather than
      // an explicit project path, because the MCP root matching uses URI comparison.
      
      test('dart_query stats returns index statistics', () async {
        final result = await env.callTool('dart_query', {
          'query': 'stats',
        });

        // Debug: print result content if it fails
        if (result.isError == true) {
          fail('Query failed: ${result.textContent}');
        }
        expect(result.textContent, contains('Index Statistics'));
        expect(result.textContent, contains('Files:'));
        expect(result.textContent, contains('Symbols:'));
      });

      test('dart_query find * returns symbols', () async {
        final result = await env.callTool('dart_query', {'query': 'find *'});

        if (result.isError == true) {
          fail('Query failed: ${result.textContent}');
        }
        expect(result.textContent, contains('MyClass'));
        expect(result.textContent, contains('main'));
      });

      test('dart_query def finds definition', () async {
        final result = await env.callTool('dart_query', {'query': 'def MyClass'});

        if (result.isError == true) {
          fail('Query failed: ${result.textContent}');
        }
        expect(result.textContent, contains('MyClass'));
        expect(result.textContent, contains('lib/main.dart'));
      });

      test('dart_query members returns class members', () async {
        final result = await env.callTool('dart_query', {'query': 'members MyClass'});

        if (result.isError == true) {
          fail('Query failed: ${result.textContent}');
        }
        expect(result.textContent, contains('doSomething'));
      });

      test('dart_query source returns source code', () async {
        final result = await env.callTool('dart_query', {'query': 'source MyClass'});

        if (result.isError == true) {
          fail('Query failed: ${result.textContent}');
        }
        expect(result.textContent, contains('class MyClass'));
        expect(result.textContent, contains('doSomething'));
      });

      test('dart_query grep finds text in source', () async {
        final result = await env.callTool('dart_query', {'query': 'grep Hello'});

        if (result.isError == true) {
          fail('Query failed: ${result.textContent}');
        }
        expect(result.textContent, contains('Hello'));
      });

      test('dart_query which shows disambiguation', () async {
        final result = await env.callTool('dart_query', {'query': 'which main'});

        if (result.isError == true) {
          fail('Query failed: ${result.textContent}');
        }
        expect(result.textContent, contains('main'));
      });

      test('dart_query impls returns implementations', () async {
        final result = await env.callTool('dart_query', {'query': 'impls MyClass'});

        // May be empty if no implementations exist
        expect(result.isError, isNot(true));
      });

      test('dart_query hierarchy returns type hierarchy', () async {
        final result = await env.callTool('dart_query', {'query': 'hierarchy MyClass'});

        // Returns hierarchy info
        expect(result.isError, isNot(true));
        expect(result.textContent, contains('MyClass'));
      });
    });

    group('Status and Refresh', () {
      test('dart_status includes version', () async {
        final result = await env.callTool('dart_status', {});

        expect(result.textContent, contains('Dart Context Status'));
        // Version should be included
        expect(result.textContent, contains('v'));
      });

      test('dart_status shows recommendations section', () async {
        final result = await env.callTool('dart_status', {});

        // Should have recommendations or available indexes
        expect(result.textContent, contains('Available Indexes'));
      });

      test('dart_refresh with fullReindex flag works', () async {
        final result = await env.callTool('dart_refresh', {
          'fullReindex': true,
        });

        // Should return some response
        expect(result.textContent.isNotEmpty, isTrue);
      });
    });

    group('Error Handling', () {
      test('dart_query with invalid syntax returns result', () async {
        final result = await env.callTool('dart_query', {
          'query': 'invalidcommand xyz',
        });

        // Invalid commands return a result with error info in the text
        expect(result.textContent, isNotEmpty);
        expect(result.textContent, contains('Unknown'));
      });

      test('dart_index_deps without pubspec.lock fails gracefully', () async {
        final result = await env.callTool('dart_index_deps', {});

        expect(result.isError, isTrue);
        expect(result.textContent, contains('pubspec.lock'));
      });
    });
  });
}

/// Test environment for MCP integration tests.
class TestEnvironment {
  final String projectPath;

  final _clientController = StreamController<String>();
  final _serverController = StreamController<String>();

  late final _clientChannel = StreamChannel<String>.withCloseGuarantee(
    _serverController.stream,
    _clientController.sink,
  );
  late final _serverChannel = StreamChannel<String>.withCloseGuarantee(
    _clientController.stream,
    _serverController.sink,
  );

  late final TestMCPClient client;
  late final TestDartContextServer server;
  late final ServerConnection serverConnection;

  TestEnvironment(this.projectPath) {
    client = TestMCPClient();
    server = TestDartContextServer(_serverChannel);
    serverConnection = client.connectServer(_clientChannel);
  }

  Future<InitializeResult> initializeServer() async {
    // Add the project as a root
    client.addRoot(Root(uri: Uri.directory(projectPath).toString()));

    final result = await serverConnection.initialize(InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ));

    if (result.protocolVersion?.isSupported == true) {
      serverConnection.notifyInitialized(InitializedNotification());
      await server.initialized;
    }

    return result;
  }

  Future<CallToolResult> callTool(
      String name, Map<String, dynamic> arguments) async {
    return serverConnection.callTool(CallToolRequest(
      name: name,
      arguments: arguments,
    ));
  }

  Future<void> shutdown() async {
    await client.shutdown();
    await server.shutdown();
  }
}

/// Test MCP client with roots support.
base class TestMCPClient extends MCPClient with RootsSupport {
  TestMCPClient()
      : super(Implementation(name: 'test_client', version: '1.0.0'));
}

/// Test MCP server with CodeContextSupport.
base class TestDartContextServer extends MCPServer
    with LoggingSupport, ToolsSupport, RootsTrackingSupport, CodeContextSupport {
  TestDartContextServer(super.channel)
      : super.fromStreamChannel(
          implementation: Implementation(
            name: 'test_dart_context_server',
            version: '1.0.0',
          ),
          instructions: 'Test server for dart_context',
        );
}

extension on CallToolResult {
  String get textContent {
    final textContents = content.whereType<TextContent>();
    return textContents.map((c) => c.text).join('\n');
  }
}
