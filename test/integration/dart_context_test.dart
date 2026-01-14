import 'dart:convert';
import 'dart:io';

import 'package:code_context/code_context.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('DartContext', () {
    late Directory tempDir;
    late String projectPath;

    setUpAll(() async {
      // Create a temporary directory for the test project
      tempDir = await Directory.systemTemp.createTemp('dart_context_e2e_');
      projectPath = tempDir.path;

      // Create a test project
      await _createTestProject(projectPath);
    });

    tearDownAll(() async {
      // Clean up
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('open creates context and indexes project', () async {
      final context = await CodeContext.open(projectPath, watch: false);

      try {
        expect(context.rootPath, projectPath);
        expect(context.stats['files'], greaterThan(0));
        expect(context.stats['symbols'], greaterThan(0));
      } finally {
        await context.dispose();
      }
    });

    group('query DSL end-to-end', () {
      late CodeContext context;

      setUpAll(() async {
        context = await CodeContext.open(projectPath, watch: false);
      });

      tearDownAll(() async {
        await context.dispose();
      });

      test('def returns definition with source', () async {
        final result = await context.query('def UserRepository');
        expect(result, isA<DefinitionResult>());

        final defResult = result as DefinitionResult;
        expect(defResult.isEmpty, isFalse);
        expect(defResult.definitions.first.source, contains('class UserRepository'));

        // Test toText format
        final text = result.toText();
        expect(text, contains('UserRepository'));
        expect(text, contains('class'));
        expect(text, contains('```dart'));
      });

      test('refs returns references or not found', () async {
        final result = await context.query('refs UserRepository');
        // May return ReferencesResult, AggregatedReferencesResult, or NotFoundResult
        expect(
          result,
          anyOf(
            isA<ReferencesResult>(),
            isA<AggregatedReferencesResult>(),
            isA<NotFoundResult>(),
          ),
        );

        // Test toText format - contains either "References" or "No references"
        final text = result.toText();
        expect(text, anyOf(contains('References'), contains('references')));
      });

      test('find with kind filter', () async {
        final result = await context.query('find * kind:class');
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        expect(searchResult.symbols, isNotEmpty);

        // All should be classes
        for (final sym in searchResult.symbols) {
          expect(sym.kindString, 'class');
        }
      });

      test('find with path filter', () async {
        final result = await context.query('find * kind:class in:lib/services/');
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        // All should be in lib/services/
        for (final sym in searchResult.symbols) {
          expect(sym.file, startsWith('lib/services/'));
        }
      });

      test('find with pattern', () async {
        final result = await context.query('find *Service kind:class');
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        expect(
          searchResult.symbols.every((s) => s.name.endsWith('Service')),
          isTrue,
        );
      });

      test('hierarchy returns supertypes and subtypes', () async {
        final result = await context.query('hierarchy UserService');
        expect(result, isA<HierarchyResult>());

        final hierarchyResult = result as HierarchyResult;
        // UserService implements BaseService
        expect(
          hierarchyResult.supertypes.map((s) => s.name),
          contains('BaseService'),
        );
      });

      test('impls returns implementations', () async {
        final result = await context.query('impls BaseService');
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        expect(
          searchResult.symbols.map((s) => s.name),
          contains('UserService'),
        );
      });

      test('source returns source code', () async {
        final result = await context.query('source UserRepository');
        expect(result, isA<SourceResult>());

        final sourceResult = result as SourceResult;
        expect(sourceResult.source, contains('class UserRepository'));
        expect(sourceResult.file, contains('user_repository.dart'));
      });

      test('files lists all indexed files', () async {
        final result = await context.query('files');
        expect(result, isA<FilesResult>());

        final filesResult = result as FilesResult;
        expect(filesResult.files, contains('lib/main.dart'));
        expect(
          filesResult.files.any((f) => f.contains('user_repository.dart')),
          isTrue,
        );
      });

      test('stats returns statistics', () async {
        final result = await context.query('stats');
        expect(result, isA<StatsResult>());

        final statsResult = result as StatsResult;
        expect(statsResult.stats['files'], greaterThan(0));
        expect(statsResult.stats['symbols'], greaterThan(0));
        expect(statsResult.stats['references'], greaterThan(0));
      });

      test('invalid query returns error', () async {
        final result = await context.query('invalid_action foo');
        expect(result, isA<ErrorResult>());
      });

      test('not found returns appropriate message', () async {
        final result = await context.query('def NonExistentSymbol123');
        expect(result, isA<NotFoundResult>());
      });
    });

    group('JSON output', () {
      late CodeContext context;

      setUpAll(() async {
        context = await CodeContext.open(projectPath, watch: false);
      });

      tearDownAll(() async {
        await context.dispose();
      });

      test('toJson can be serialized for all result types', () async {
        final queries = [
          'def UserRepository',
          'refs UserRepository',
          'find * kind:class',
          'hierarchy UserService',
          'source UserRepository',
          'files',
          'stats',
          'def NonExistent',
        ];

        for (final query in queries) {
          final result = await context.query(query);
          final json = result.toJson();

          // Should be valid JSON
          expect(() => jsonEncode(json), returnsNormally);

          // Should have type field
          expect(json, contains('type'));
        }
      });

      test('DefinitionResult JSON has expected fields', () async {
        final result = await context.query('def UserRepository');
        final json = result.toJson();

        expect(json['type'], 'definitions');
        expect(json['count'], isA<int>());
        expect(json['results'], isA<List>());

        if ((json['results'] as List).isNotEmpty) {
          final first = json['results'][0] as Map;
          expect(first, contains('symbol'));
          expect(first, contains('name'));
          expect(first, contains('kind'));
          expect(first, contains('file'));
          expect(first, contains('line'));
        }
      });

      test('ReferencesResult JSON has expected fields', () async {
        final result = await context.query('refs UserRepository');
        final json = result.toJson();

        // May be 'references' or 'aggregated_references' depending on matches
        expect(json['type'], anyOf('references', 'aggregated_references'));
        if (json['type'] == 'references') {
          expect(json, contains('symbol'));
          expect(json, contains('name'));
          expect(json['results'], isA<List>());
        } else {
          expect(json, contains('query'));
          expect(json, contains('symbols'));
        }
      });

      test('SearchResult JSON has expected fields', () async {
        final result = await context.query('find * kind:class');
        final json = result.toJson();

        expect(json['type'], 'search');
        expect(json['count'], isA<int>());
        expect(json['results'], isA<List>());
      });
    });

    group('index access', () {
      late CodeContext context;

      setUpAll(() async {
        context = await CodeContext.open(projectPath, watch: false);
      });

      tearDownAll(() async {
        await context.dispose();
      });

      test('exposes index for direct queries', () {
        final index = context.index;
        expect(index, isNotNull);
        expect(index.stats['files'], greaterThan(0));
      });

      test('index can be used for programmatic queries', () {
        final index = context.index;

        // Find by pattern
        final symbols = index.findSymbols('User*').toList();
        expect(symbols, isNotEmpty);

        // Get symbol info
        final userRepo = symbols.firstWhere(
          (s) => s.name == 'UserRepository',
          orElse: () => throw StateError('UserRepository not found'),
        );
        expect(userRepo.kindString, 'class');
        expect(userRepo.file, contains('user_repository.dart'));
      });
    });
  });
}

/// Creates a more complex test project for end-to-end testing.
Future<void> _createTestProject(String projectPath) async {
  // Create pubspec.yaml
  await File(p.join(projectPath, 'pubspec.yaml')).writeAsString('''
name: test_project
description: A test project for dart_context integration tests.
version: 1.0.0

environment:
  sdk: ^3.0.0
''');

  // Create directories
  await Directory(p.join(projectPath, 'lib', 'models')).create(recursive: true);
  await Directory(p.join(projectPath, 'lib', 'services'))
      .create(recursive: true);
  await Directory(p.join(projectPath, 'lib', 'repositories'))
      .create(recursive: true);

  // Create main.dart
  await File(p.join(projectPath, 'lib', 'main.dart')).writeAsString('''
import 'models/user.dart';
import 'repositories/user_repository.dart';
import 'services/user_service.dart';

void main() {
  final repository = UserRepository();
  final service = UserService(repository);

  final user = service.createUser('John', 'john@example.com');
  print('Created user: \${user.name}');
}
''');

  // Create user.dart
  await File(p.join(projectPath, 'lib', 'models', 'user.dart'))
      .writeAsString('''
/// Represents a user in the system.
class User {
  final String id;
  final String name;
  final String email;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    required this.email,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  User copyWith({
    String? name,
    String? email,
  }) {
    return User(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt,
    );
  }

  @override
  String toString() => 'User(id: \$id, name: \$name, email: \$email)';
}
''');

  // Create user_repository.dart
  await File(p.join(projectPath, 'lib', 'repositories', 'user_repository.dart'))
      .writeAsString('''
import '../models/user.dart';

/// Repository for managing user data.
class UserRepository {
  final Map<String, User> _users = {};
  int _nextId = 1;

  User create(String name, String email) {
    final id = (_nextId++).toString();
    final user = User(id: id, name: name, email: email);
    _users[id] = user;
    return user;
  }

  User? findById(String id) {
    return _users[id];
  }

  User? findByEmail(String email) {
    return _users.values.cast<User?>().firstWhere(
          (u) => u?.email == email,
          orElse: () => null,
        );
  }

  List<User> findAll() {
    return _users.values.toList();
  }

  User? update(String id, {String? name, String? email}) {
    final user = _users[id];
    if (user == null) return null;

    final updated = user.copyWith(name: name, email: email);
    _users[id] = updated;
    return updated;
  }

  bool delete(String id) {
    return _users.remove(id) != null;
  }
}
''');

  // Create base_service.dart
  await File(p.join(projectPath, 'lib', 'services', 'base_service.dart'))
      .writeAsString('''
/// Base interface for services.
abstract class BaseService {
  void initialize();
  void dispose();
}
''');

  // Create user_service.dart
  await File(p.join(projectPath, 'lib', 'services', 'user_service.dart'))
      .writeAsString('''
import '../models/user.dart';
import '../repositories/user_repository.dart';
import 'base_service.dart';

/// Service for user-related operations.
class UserService implements BaseService {
  final UserRepository _repository;

  UserService(this._repository);

  @override
  void initialize() {
    // Initialize service
  }

  @override
  void dispose() {
    // Clean up resources
  }

  User createUser(String name, String email) {
    // Validate email
    if (!email.contains('@')) {
      throw ArgumentError('Invalid email format');
    }

    // Check for duplicate
    final existing = _repository.findByEmail(email);
    if (existing != null) {
      throw StateError('User with email already exists');
    }

    return _repository.create(name, email);
  }

  User? getUser(String id) {
    return _repository.findById(id);
  }

  List<User> getAllUsers() {
    return _repository.findAll();
  }

  User? updateUser(String id, {String? name, String? email}) {
    if (email != null && !email.contains('@')) {
      throw ArgumentError('Invalid email format');
    }
    return _repository.update(id, name: name, email: email);
  }

  bool deleteUser(String id) {
    return _repository.delete(id);
  }
}
''');

  // Run dart pub get to create package_config.json
  final result = await Process.run(
    'dart',
    ['pub', 'get'],
    workingDirectory: projectPath,
  );

  if (result.exitCode != 0) {
    throw StateError(
      'Failed to run dart pub get: ${result.stderr}',
    );
  }
}

