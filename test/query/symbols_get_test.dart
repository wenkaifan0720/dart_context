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

  group('ScipQuery parsing for symbols', () {
    test('parses symbols command', () {
      final query = ScipQuery.parse('symbols lib/auth.dart');

      expect(query.action, QueryAction.symbols);
      expect(query.target, 'lib/auth.dart');
    });
  });
}
