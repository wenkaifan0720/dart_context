import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

import '../fixtures/mock_scip_index.dart';

void main() {
  group('ContextExtractor', () {
    group('with basic index', () {
      late ScipIndex index;
      late ContextExtractor extractor;

      setUp(() {
        index = MockScipIndex.basic();
        extractor = ContextExtractor(index);
      });

      test('extracts folder context with path', () {
        final context = extractor.extractFolder('lib/features/auth');

        expect(context.path, 'lib/features/auth');
      });

      test('extracts files in folder', () {
        final context = extractor.extractFolder('lib/features/auth');

        expect(context.files, hasLength(1));
        expect(context.files.first.path, 'lib/features/auth/auth_service.dart');
      });

      test('extracts public API from files', () {
        final context = extractor.extractFolder('lib/features/auth');

        final file = context.files.first;
        expect(file.publicApi, hasLength(1));
        expect(file.publicApi.first.name, 'AuthService');
        expect(file.publicApi.first.kind, 'class');
      });

      test('extracts symbol summaries', () {
        final context = extractor.extractFolder('lib/features/auth');

        final file = context.files.first;
        expect(file.symbols, hasLength(2)); // AuthService + login method
        expect(file.symbols.any((s) => s.name == 'AuthService'), isTrue);
        expect(file.symbols.any((s) => s.name == 'login'), isTrue);
      });

      test('handles non-existent folder gracefully', () {
        final context = extractor.extractFolder('lib/nonexistent');

        expect(context.path, 'lib/nonexistent');
        expect(context.files, isEmpty);
        expect(context.internalDeps, isEmpty);
        expect(context.externalDeps, isEmpty);
      });

      test('extracts core folder', () {
        final context = extractor.extractFolder('lib/core');

        expect(context.files, hasLength(1));
        expect(context.files.first.publicApi.first.name, 'ApiClient');
      });
    });

    group('with dependency index', () {
      late ScipIndex index;
      late ContextExtractor extractor;

      setUp(() {
        index = MockScipIndex.withDependencies();
        extractor = ContextExtractor(index);
      });

      test('detects internal dependencies', () {
        final context = extractor.extractFolder('lib/features/auth');

        // Auth folder should depend on core folder (uses Helper)
        expect(context.internalDeps, contains('lib/core'));
      });

      test('tracks used symbols per dependency', () {
        final context = extractor.extractFolder('lib/features/auth');

        expect(context.usedSymbols.containsKey('lib/core'), isTrue);
        expect(context.usedSymbols['lib/core'], contains('Helper'));
      });
    });

    group('with external deps index', () {
      late ScipIndex index;
      late ContextExtractor extractor;

      setUp(() {
        index = MockScipIndex.withExternalDeps();
        extractor = ContextExtractor(index);
      });

      test('detects external package dependencies', () {
        final context = extractor.extractFolder('lib/features/auth');

        expect(context.externalDeps, contains('firebase_auth'));
      });

      test('tracks used symbols from external packages', () {
        final context = extractor.extractFolder('lib/features/auth');

        expect(context.usedSymbols.containsKey('firebase_auth'), isTrue);
        expect(context.usedSymbols['firebase_auth'], contains('FirebaseAuth'));
      });
    });
  });

  group('FileContext', () {
    test('toJson includes all fields', () {
      final fileContext = FileContext(
        path: 'lib/test.dart',
        docComments: ['/// Module doc'],
        publicApi: [
          const ApiSignature(
            name: 'TestClass',
            kind: 'class',
            signature: 'class TestClass',
            docComment: 'A test class',
          ),
        ],
        symbols: [
          const SymbolSummary(
            id: 'scip://lib/test.dart/TestClass#',
            name: 'TestClass',
            kind: 'class',
          ),
        ],
      );

      final json = fileContext.toJson();

      expect(json['path'], 'lib/test.dart');
      expect(json['docComments'], ['/// Module doc']);
      expect(json['publicApi'], hasLength(1));
      expect(json['symbols'], hasLength(1));
    });

    test('toJson omits empty docComments', () {
      final fileContext = FileContext(
        path: 'lib/test.dart',
        docComments: [],
        publicApi: [],
        symbols: [],
      );

      final json = fileContext.toJson();

      expect(json.containsKey('docComments'), isFalse);
    });
  });

  group('FolderContext', () {
    test('toJson produces valid structure', () {
      final folderContext = FolderContext(
        path: 'lib/test',
        files: [],
        internalDeps: {'lib/core'},
        externalDeps: {'http'},
        usedSymbols: {
          'lib/core': ['Helper'],
          'http': ['Client'],
        },
      );

      final json = folderContext.toJson();

      expect(json['path'], 'lib/test');
      expect(json['files'], isEmpty);
      expect(json['internalDeps'], contains('lib/core'));
      expect(json['externalDeps'], contains('http'));
      expect(json['usedSymbols']['lib/core'], contains('Helper'));
    });

    test('toJson sorts dependencies', () {
      final folderContext = FolderContext(
        path: 'lib/test',
        files: [],
        internalDeps: {'lib/z', 'lib/a', 'lib/m'},
        externalDeps: {'zebra', 'alpha'},
        usedSymbols: {},
      );

      final json = folderContext.toJson();

      expect(json['internalDeps'], ['lib/a', 'lib/m', 'lib/z']);
      expect(json['externalDeps'], ['alpha', 'zebra']);
    });
  });

  group('SymbolSummary', () {
    test('toJson includes relationships', () {
      const summary = SymbolSummary(
        id: 'scip://test#',
        name: 'Test',
        kind: 'class',
        signature: 'class Test',
        docComment: 'A test',
        relationships: [
          SymbolRelationship(
            targetId: 'scip://base#',
            targetName: 'Base',
            kind: 'implements',
          ),
        ],
      );

      final json = summary.toJson();

      expect(json['id'], 'scip://test#');
      expect(json['name'], 'Test');
      expect(json['signature'], 'class Test');
      expect(json['docComment'], 'A test');
      expect(json['relationships'], hasLength(1));
      expect(json['relationships'][0]['kind'], 'implements');
    });

    test('toJson omits null fields', () {
      const summary = SymbolSummary(
        id: 'scip://test#',
        name: 'Test',
        kind: 'class',
      );

      final json = summary.toJson();

      expect(json.containsKey('signature'), isFalse);
      expect(json.containsKey('docComment'), isFalse);
      expect(json.containsKey('relationships'), isFalse);
    });
  });

  group('ApiSignature', () {
    test('toJson includes all fields', () {
      const api = ApiSignature(
        name: 'MyClass',
        kind: 'class',
        signature: 'class MyClass extends Base',
        docComment: 'My class docs',
      );

      final json = api.toJson();

      expect(json['name'], 'MyClass');
      expect(json['kind'], 'class');
      expect(json['signature'], 'class MyClass extends Base');
      expect(json['docComment'], 'My class docs');
    });

    test('toJson omits null docComment', () {
      const api = ApiSignature(
        name: 'MyClass',
        kind: 'class',
        signature: 'class MyClass',
      );

      final json = api.toJson();

      expect(json.containsKey('docComment'), isFalse);
    });
  });
}
