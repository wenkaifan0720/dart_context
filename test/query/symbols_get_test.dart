// Tests for symbols and get queries
// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:code_context/code_context.dart';
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:test/test.dart';

void main() {
  group('symbols query', () {
    late Directory tempDir;
    late ScipIndex index;
    late QueryExecutor executor;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('symbols_test_');

      // Create test files
      final libDir = Directory('${tempDir.path}/lib');
      await libDir.create();

      await File('${libDir.path}/service.dart').writeAsString('''
class AuthService {
  void login() {}
  void logout() {}
}

class UserService {
  String getName() => 'user';
}
''');

      await File('${libDir.path}/models.dart').writeAsString('''
class User {
  final String name;
  User(this.name);
}

enum Role { admin, user, guest }
''');

      // Create index with test symbols using updateDocument
      index = ScipIndex.empty(projectRoot: tempDir.path);

      // Add symbols for service.dart
      index.updateDocument(
        scip.Document(
          relativePath: 'lib/service.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'dart pub test lib/service.dart/AuthService#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'AuthService',
              documentation: ['Auth service for handling authentication'],
            ),
            scip.SymbolInformation(
              symbol: 'dart pub test lib/service.dart/AuthService#login().',
              kind: scip.SymbolInformation_Kind.Method,
              displayName: 'login',
            ),
            scip.SymbolInformation(
              symbol: 'dart pub test lib/service.dart/AuthService#logout().',
              kind: scip.SymbolInformation_Kind.Method,
              displayName: 'logout',
            ),
            scip.SymbolInformation(
              symbol: 'dart pub test lib/service.dart/UserService#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'UserService',
            ),
            scip.SymbolInformation(
              symbol: 'dart pub test lib/service.dart/UserService#getName().',
              kind: scip.SymbolInformation_Kind.Method,
              displayName: 'getName',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'dart pub test lib/service.dart/AuthService#',
              range: [1, 6, 1, 17],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
            scip.Occurrence(
              symbol: 'dart pub test lib/service.dart/UserService#',
              range: [7, 6, 7, 17],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          ],
        ),
      );

      // Add symbols for models.dart
      index.updateDocument(
        scip.Document(
          relativePath: 'lib/models.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'dart pub test lib/models.dart/User#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'User',
            ),
            scip.SymbolInformation(
              symbol: 'dart pub test lib/models.dart/User#name.',
              kind: scip.SymbolInformation_Kind.Field,
              displayName: 'name',
            ),
            scip.SymbolInformation(
              symbol: 'dart pub test lib/models.dart/Role#',
              kind: scip.SymbolInformation_Kind.Enum,
              displayName: 'Role',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'dart pub test lib/models.dart/User#',
              range: [1, 6, 1, 10],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
            scip.Occurrence(
              symbol: 'dart pub test lib/models.dart/Role#',
              range: [6, 5, 6, 9],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          ],
        ),
      );

      executor = QueryExecutor(index);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('lists all symbols in a file', () async {
      final result = await executor.execute('symbols lib/service.dart');

      expect(result, isA<FileSymbolsResult>());
      final symbolsResult = result as FileSymbolsResult;

      expect(symbolsResult.file, 'lib/service.dart');
      expect(symbolsResult.symbols.length, greaterThanOrEqualTo(2));

      final names = symbolsResult.symbols.map((s) => s.name).toList();
      expect(names, containsAll(['AuthService', 'UserService']));
    });

    test('lists symbols in models file', () async {
      final result = await executor.execute('symbols lib/models.dart');

      expect(result, isA<FileSymbolsResult>());
      final symbolsResult = result as FileSymbolsResult;

      final names = symbolsResult.symbols.map((s) => s.name).toList();
      expect(names, containsAll(['User', 'Role']));
    });

    test('returns not found for non-existent file', () async {
      final result = await executor.execute('symbols lib/nonexistent.dart');

      // Non-existent files return NotFoundResult or FileSymbolsResult with empty symbols
      expect(result, anyOf(isA<NotFoundResult>(), isA<FileSymbolsResult>()));
      if (result is FileSymbolsResult) {
        expect(result.symbols, isEmpty);
      }
    });

    test('toText formats correctly', () async {
      final result = await executor.execute('symbols lib/service.dart');
      final text = result.toText();

      expect(text, contains('lib/service.dart'));
      expect(text, contains('AuthService'));
    });

    test('toJson returns structured data', () async {
      final result = await executor.execute('symbols lib/service.dart');
      final json = result.toJson();

      expect(json['file'], 'lib/service.dart');
      expect(json['symbols'], isA<List>());
    });
  });

  group('get query', () {
    late ScipIndex index;
    late QueryExecutor executor;

    setUp(() {
      index = ScipIndex.empty(projectRoot: '/test/project');

      // Add some symbols using updateDocument
      index.updateDocument(
        scip.Document(
          relativePath: 'lib/auth.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'dart pub test lib/auth.dart/AuthService#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'AuthService',
              documentation: ['Authentication service'],
            ),
            scip.SymbolInformation(
              symbol: 'dart pub test lib/auth.dart/AuthService#login().',
              kind: scip.SymbolInformation_Kind.Method,
              displayName: 'login',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'dart pub test lib/auth.dart/AuthService#',
              range: [10, 6, 10, 17],
              symbolRoles: scip.SymbolRole.Definition.value,
              enclosingRange: [10, 0, 50, 1],
            ),
            scip.Occurrence(
              symbol: 'dart pub test lib/auth.dart/AuthService#login().',
              range: [15, 8, 15, 13],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          ],
        ),
      );

      index.updateDocument(
        scip.Document(
          relativePath: 'lib/user.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'dart pub test lib/user.dart/User#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'User',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'dart pub test lib/user.dart/User#',
              range: [5, 6, 5, 10],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          ],
        ),
      );

      executor = QueryExecutor(index);
    });

    test('gets symbol by exact SCIP ID', () async {
      final result = await executor.execute(
        'get "dart pub test lib/auth.dart/AuthService#"',
      );

      expect(result, isA<DefinitionResult>());
      final defResult = result as DefinitionResult;

      expect(defResult.definitions.length, 1);
      expect(defResult.definitions.first.symbol.name, 'AuthService');
    });

    test('returns not found for unknown ID', () async {
      final result = await executor.execute(
        'get "dart pub nonexistent lib/foo.dart/Unknown#"',
      );

      expect(result, isA<NotFoundResult>());
    });

    test('works with method symbols', () async {
      final result = await executor.execute(
        'get "dart pub test lib/auth.dart/AuthService#login()."',
      );

      expect(result, isA<DefinitionResult>());
      final defResult = result as DefinitionResult;

      expect(defResult.definitions.first.symbol.name, 'login');
    });

    test('toText formats correctly', () async {
      final result = await executor.execute(
        'get "dart pub test lib/auth.dart/AuthService#"',
      );
      final text = result.toText();

      expect(text, contains('AuthService'));
    });

    test('toJson returns structured data', () async {
      final result = await executor.execute(
        'get "dart pub test lib/auth.dart/AuthService#"',
      );
      final json = result.toJson();

      expect(json['type'], 'definitions');
      expect(json['results'], isA<List>());
      expect((json['results'] as List).length, 1);
    });

    test('handles quotes in symbol ID', () async {
      // Symbol IDs with spaces need quotes
      final result = await executor.execute(
        'get "dart pub test lib/user.dart/User#"',
      );

      expect(result, isA<DefinitionResult>());
      final defResult = result as DefinitionResult;
      expect(defResult.definitions.first.symbol.name, 'User');
    });
  });

  group('ScipQuery parsing for symbols and get', () {
    test('parses symbols command', () {
      final query = ScipQuery.parse('symbols lib/auth.dart');

      expect(query.action, QueryAction.symbols);
      expect(query.target, 'lib/auth.dart');
    });

    test('parses get command with quoted ID', () {
      final query = ScipQuery.parse('get "dart pub test lib/foo.dart/Foo#"');

      expect(query.action, QueryAction.get);
      expect(query.target, 'dart pub test lib/foo.dart/Foo#');
    });

    test('parses get command with simple ID', () {
      final query = ScipQuery.parse('get scip-dart#Foo');

      expect(query.action, QueryAction.get);
      expect(query.target, 'scip-dart#Foo');
    });
  });
}
