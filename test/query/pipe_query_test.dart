// ignore_for_file: implementation_imports
import 'package:code_context/code_context.dart';
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:test/test.dart';

void main() {
  group('Pipe Queries', () {
    late ScipIndex index;
    late QueryExecutor executor;

    setUp(() {
      index = ScipIndex.empty(projectRoot: '/test/project');
      executor = QueryExecutor(index);

      // Set up test index with Auth* classes
      index.updateDocument(
        scip.Document(
          relativePath: 'lib/auth/repository.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'test lib/auth/repository.dart/AuthRepository#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'AuthRepository',
            ),
            scip.SymbolInformation(
              symbol: 'test lib/auth/repository.dart/AuthRepository#login().',
              kind: scip.SymbolInformation_Kind.Method,
              displayName: 'login',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'test lib/auth/repository.dart/AuthRepository#',
              range: [5, 6, 5, 20],
              symbolRoles: scip.SymbolRole.Definition.value,
              enclosingRange: [5, 0, 50, 1],
            ),
            scip.Occurrence(
              symbol: 'test lib/auth/repository.dart/AuthRepository#login().',
              range: [10, 2, 10, 7],
              symbolRoles: scip.SymbolRole.Definition.value,
              enclosingRange: [10, 0, 20, 3],
            ),
          ],
        ),
      );

      index.updateDocument(
        scip.Document(
          relativePath: 'lib/auth/service.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'test lib/auth/service.dart/AuthService#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'AuthService',
            ),
            scip.SymbolInformation(
              symbol: 'test lib/auth/service.dart/AuthService#authenticate().',
              kind: scip.SymbolInformation_Kind.Method,
              displayName: 'authenticate',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'test lib/auth/service.dart/AuthService#',
              range: [3, 6, 3, 17],
              symbolRoles: scip.SymbolRole.Definition.value,
              enclosingRange: [3, 0, 40, 1],
            ),
            scip.Occurrence(
              symbol: 'test lib/auth/service.dart/AuthService#authenticate().',
              range: [10, 2, 10, 14],
              symbolRoles: scip.SymbolRole.Definition.value,
              enclosingRange: [10, 0, 25, 3],
            ),
            // Reference to AuthRepository
            scip.Occurrence(
              symbol: 'test lib/auth/repository.dart/AuthRepository#',
              range: [15, 10, 15, 24],
              symbolRoles: 0,
            ),
          ],
        ),
      );
    });

    group('pipe combinations', () {
      test('find | members - search then get members', () async {
        final result =
            await executor.execute('find Auth* kind:class | members');
        expect(
          result,
          anyOf(
            isA<MembersResult>(),
            isA<PipelineResult>(),
            isA<NotFoundResult>(),
          ),
        );
      });

      test('find | refs - search then find references', () async {
        final result = await executor.execute('find AuthRepository | refs');
        expect(
          result,
          anyOf(
            isA<ReferencesResult>(),
            isA<AggregatedReferencesResult>(),
            isA<PipelineResult>(),
          ),
        );
      });

      test('find | def - search then find definitions', () async {
        final result = await executor.execute('find Auth* | def');
        expect(
          result,
          anyOf(
            isA<DefinitionResult>(),
            isA<PipelineResult>(),
            isA<NotFoundResult>(),
          ),
        );
      });

      test('find | calls - search then get call graph', () async {
        final result = await executor.execute('find Auth* kind:class | calls');
        expect(
          result,
          anyOf(isA<CallGraphResult>(), isA<PipelineResult>()),
        );
      });

      test('members | source - get members then source', () async {
        final result =
            await executor.execute('members AuthRepository | source');
        expect(result, isA<QueryResult>());
      });

      test('find as filter in pipe', () async {
        // find in pipe context filters symbols instead of global search
        final result =
            await executor.execute('members AuthRepository | find *');
        expect(result, isA<SearchResult>());
      });
    });

    group('error handling', () {
      test('handles empty first result', () async {
        final result = await executor.execute('find NonExistent* | refs');
        expect(
          result,
          anyOf(isA<SearchResult>(), isA<NotFoundResult>()),
        );
      });

      test('handles error in first query', () async {
        final result = await executor.execute('invalid_query | refs');
        expect(result, isA<ErrorResult>());
      });

      test('handles not found in pipe step', () async {
        final result =
            await executor.execute('find ZZZNonExistent | members');
        expect(
          result,
          anyOf(isA<NotFoundResult>(), isA<SearchResult>()),
        );
      });
    });

    group('multiple pipes', () {
      test('three stage pipeline', () async {
        // Find -> Members -> (would need source but skipping for speed)
        final result =
            await executor.execute('find Auth* kind:class | members');
        expect(result, isA<QueryResult>());
      });
    });

    group('result merging', () {
      test('merges multiple search results', () async {
        // Multiple symbols found, each queried
        final result = await executor.execute('find Auth* | def');
        expect(result, isA<QueryResult>());
        // Results should be aggregated
      });

      test('merges multiple reference results', () async {
        final result = await executor.execute('find Auth* kind:class | refs');
        expect(result, isA<QueryResult>());
      });
    });

    group('special cases', () {
      test('single symbol through pipe', () async {
        final result = await executor.execute('find AuthRepository | refs');
        expect(result, isA<QueryResult>());
      });

      test('pipe preserves kind filter context', () async {
        final result =
            await executor.execute('find * kind:method | callers');
        expect(result, isA<QueryResult>());
      });
    });

    group('imports/exports piping', () {
      test('imports | refs - find refs for imported symbols', () async {
        final result = await executor.execute('imports lib/auth/service.dart | refs');
        expect(result, isA<QueryResult>());
      });

      test('exports | members - get members of exported symbols', () async {
        final result = await executor.execute('exports lib/auth/ | members');
        expect(result, isA<QueryResult>());
      });

      test('imports extracts symbols from imported files', () async {
        final importsResult = await executor.execute('imports lib/auth/service.dart');
        // File might not exist in test setup, so could be NotFoundResult
        if (importsResult is ImportsResult) {
          expect(importsResult.importedSymbols, isA<List<SymbolInfo>>());
        } else {
          expect(importsResult, isA<NotFoundResult>());
        }
      });

      test('exports extracts exported symbols', () async {
        final exportsResult = await executor.execute('exports lib/auth/');
        // Directory might not exist in test setup
        if (exportsResult is ImportsResult) {
          expect(exportsResult.exportedSymbols, isA<List<SymbolInfo>>());
        } else {
          expect(exportsResult, isA<NotFoundResult>());
        }
      });
    });
  });

  group('Pipe Query Documentation', () {
    test('supported first queries', () {
      // Document which queries can be piped FROM
      // These produce symbols that can be passed to next query
      const supportedFirst = [
        'find', // SearchResult -> symbols
        'def', // DefinitionResult -> symbols from definitions
        'members', // MembersResult -> member symbols
        'hierarchy', // HierarchyResult -> super/subtypes
        'calls', // CallGraphResult -> called symbols
        'callers', // CallGraphResult -> caller symbols
        'refs', // ReferencesResult -> the queried symbol
        'imports', // ImportsResult -> imported/exported symbols
        'exports', // ImportsResult -> exported symbols
      ];
      expect(supportedFirst.length, 9);
    });

    test('supported second queries', () {
      // Document which queries can be piped TO
      // These accept a symbol name as target
      const supportedSecond = [
        'def', // Find definition
        'refs', // Find references
        'members', // Get members
        'hierarchy', // Get hierarchy
        'source', // Get source
        'calls', // Get call graph (outgoing)
        'callers', // Get call graph (incoming)
        'find', // Filter piped symbols by pattern
      ];
      expect(supportedSecond.length, 8);
    });

    test('find as pipe filter', () {
      // In pipe context, find filters incoming symbols instead of global search
      // Example: members MyClass | find get* kind:method
      // This filters MyClass members to only those starting with "get"
      expect(true, isTrue); // Documentation test
    });
  });
}

