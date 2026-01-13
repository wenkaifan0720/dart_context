import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scip_server/src/docs/llm/doc_tools.dart';
import 'package:scip_server/src/index/scip_index.dart';
import 'package:test/test.dart';

void main() {
  group('DocToolRegistry', () {
    late Directory tempDir;
    late ScipIndex emptyIndex;
    late DocToolRegistry registry;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('doc_tools_test_');
      emptyIndex = ScipIndex.empty(projectRoot: tempDir.path);
      registry = DocToolRegistry(
        projectRoot: tempDir.path,
        scipIndex: emptyIndex,
        docsPath: '${tempDir.path}/.dart_context/docs',
      );
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('tools list contains all expected tools', () {
      final tools = registry.tools;

      expect(tools.length, equals(5));
      expect(tools.map((t) => t.name).toSet(), equals({
        'list_folder',
        'read_file',
        'query_scip',
        'read_subfolder_doc',
        'get_public_api',
      }));
    });

    test('list_folder returns folder contents', () async {
      // Create test structure
      final libDir = Directory(p.join(tempDir.path, 'lib'));
      await libDir.create();
      await File(p.join(libDir.path, 'main.dart')).writeAsString('// Main');
      await Directory(p.join(libDir.path, 'src')).create();

      final result = await registry.executeTool('list_folder', {
        'path': 'lib',
      });

      expect(result, contains('lib'));
      expect(result, contains('main.dart'));
      expect(result, contains('src'));
    });

    test('list_folder handles non-existent folder', () async {
      final result = await registry.executeTool('list_folder', {
        'path': 'nonexistent',
      });

      expect(result, contains('Error'));
      expect(result, contains('does not exist'));
    });

    test('read_file returns file content with line numbers', () async {
      final file = File(p.join(tempDir.path, 'test.dart'));
      await file.writeAsString('line 1\nline 2\nline 3');

      final result = await registry.executeTool('read_file', {
        'path': 'test.dart',
      });

      expect(result, contains('test.dart'));
      expect(result, contains('line 1'));
      expect(result, contains('line 2'));
      expect(result, contains('line 3'));
    });

    test('read_file with range', () async {
      final file = File(p.join(tempDir.path, 'test.dart'));
      await file.writeAsString('line 1\nline 2\nline 3\nline 4\nline 5');

      final result = await registry.executeTool('read_file', {
        'path': 'test.dart',
        'start_line': 2,
        'end_line': 4,
      });

      expect(result, contains('Lines: 2-4'));
      expect(result, contains('line 2'));
      expect(result, contains('line 3'));
      expect(result, contains('line 4'));
    });

    test('read_file handles non-existent file', () async {
      final result = await registry.executeTool('read_file', {
        'path': 'nonexistent.dart',
      });

      expect(result, contains('Error'));
      expect(result, contains('does not exist'));
    });

    test('query_scip definitions on empty index', () async {
      final result = await registry.executeTool('query_scip', {
        'query_type': 'definitions',
        'path': 'lib',
      });

      expect(result, contains('SCIP Query: definitions'));
      expect(result, contains('Path: lib'));
    });

    test('query_scip requires symbol for references', () async {
      final result = await registry.executeTool('query_scip', {
        'query_type': 'references',
        'path': 'lib',
      });

      expect(result, contains('Error'));
      expect(result, contains('symbol'));
      expect(result, contains('required'));
    });

    test('read_subfolder_doc when no doc exists', () async {
      final result = await registry.executeTool('read_subfolder_doc', {
        'path': 'lib/features/auth',
      });

      expect(result, contains('Error'));
      expect(result, contains('No documentation found'));
    });

    test('read_subfolder_doc when doc exists', () async {
      final docDir = Directory(p.join(
        tempDir.path, '.dart_context/docs/folders/lib/features/auth'));
      await docDir.create(recursive: true);
      await File(p.join(docDir.path, 'index.md')).writeAsString(
        '# Auth\n\nAuthentication module.',
      );

      final result = await registry.executeTool('read_subfolder_doc', {
        'path': 'lib/features/auth',
      });

      expect(result, contains('lib/features/auth'));
      expect(result, contains('# Auth'));
      expect(result, contains('Authentication module'));
    });

    test('get_public_api on empty index', () async {
      final result = await registry.executeTool('get_public_api', {
        'path': 'lib',
      });

      expect(result, contains('Public API'));
      expect(result, contains('No public API found'));
    });

    test('unknown tool returns error', () async {
      final result = await registry.executeTool('unknown_tool', {});

      expect(result, contains('Error'));
      expect(result, contains('Unknown tool'));
      expect(result, contains('Available tools'));
    });
  });
}
