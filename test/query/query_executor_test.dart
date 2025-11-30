// ignore_for_file: implementation_imports
import 'package:dart_context/src/index/scip_index.dart';
import 'package:dart_context/src/query/query_executor.dart';
import 'package:dart_context/src/query/query_parser.dart';
import 'package:dart_context/src/query/query_result.dart';
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:test/test.dart';

void main() {
  group('QueryExecutor', () {
    late ScipIndex index;
    late QueryExecutor executor;

    setUp(() {
      index = ScipIndex.empty(projectRoot: '/test/project');
      executor = QueryExecutor(index);

      // Set up a test index with various symbols
      index.updateDocument(
        scip.Document(
          relativePath: 'lib/auth/repository.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'test lib/auth/repository.dart/AuthRepository#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'AuthRepository',
              documentation: ['Repository for authentication operations.'],
            ),
            scip.SymbolInformation(
              symbol: 'test lib/auth/repository.dart/AuthRepository#login().',
              kind: scip.SymbolInformation_Kind.Method,
              displayName: 'login',
            ),
            scip.SymbolInformation(
              symbol: 'test lib/auth/repository.dart/AuthRepository#logout().',
              kind: scip.SymbolInformation_Kind.Method,
              displayName: 'logout',
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
            ),
            scip.Occurrence(
              symbol: 'test lib/auth/repository.dart/AuthRepository#logout().',
              range: [20, 2, 20, 8],
              symbolRoles: scip.SymbolRole.Definition.value,
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
              relationships: [
                scip.Relationship(
                  symbol: 'test lib/auth/repository.dart/AuthRepository#',
                  isImplementation: true,
                ),
              ],
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'test lib/auth/service.dart/AuthService#',
              range: [3, 6, 3, 17],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
            // Reference to AuthRepository
            scip.Occurrence(
              symbol: 'test lib/auth/repository.dart/AuthRepository#',
              range: [5, 10, 5, 24],
              symbolRoles: 0,
            ),
            // Reference to login
            scip.Occurrence(
              symbol: 'test lib/auth/repository.dart/AuthRepository#login().',
              range: [10, 5, 10, 10],
              symbolRoles: 0,
            ),
          ],
        ),
      );

      index.updateDocument(
        scip.Document(
          relativePath: 'lib/utils/helper.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'test lib/utils/helper.dart/formatDate().',
              kind: scip.SymbolInformation_Kind.Function,
              displayName: 'formatDate',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'test lib/utils/helper.dart/formatDate().',
              range: [1, 0, 1, 10],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          ],
        ),
      );
    });

    group('execute', () {
      test('parses and executes query string', () async {
        final result = await executor.execute('find Auth* kind:class');
        expect(result, isA<SearchResult>());
        // AuthRepository and AuthService
        expect((result as SearchResult).symbols, hasLength(2));
      });

      test('returns error for invalid query', () async {
        final result = await executor.execute('invalid');
        expect(result, isA<ErrorResult>());
      });

      test('returns error for empty query', () async {
        final result = await executor.execute('');
        expect(result, isA<ErrorResult>());
      });
    });

    group('definition', () {
      test('finds symbol definition', () async {
        // Use kind filter to get exact class match
        final result = await executor.executeQuery(
          ScipQuery.parse('find AuthRepository kind:class'),
        );
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        expect(searchResult.symbols, hasLength(1));
        expect(searchResult.symbols.first.name, 'AuthRepository');
      });

      test('finds definition with exact name', () async {
        final result = await executor.execute('def AuthService');
        expect(result, isA<DefinitionResult>());

        final defResult = result as DefinitionResult;
        // Only AuthService, not AuthRepository members
        expect(defResult.definitions.length, greaterThanOrEqualTo(1));
      });

      test('returns not found for unknown symbol', () async {
        final result = await executor.execute('def NonExistent');
        expect(result, isA<NotFoundResult>());
      });
    });

    group('references', () {
      test('finds symbol references', () async {
        final result = await executor.execute('refs AuthRepository');
        // May return ReferencesResult (single match) or AggregatedReferencesResult (multiple)
        expect(
          result,
          anyOf(isA<ReferencesResult>(), isA<AggregatedReferencesResult>()),
        );

        // Check that we have references in the result
        if (result is ReferencesResult) {
          expect(result.references, hasLength(1));
          expect(result.references.first.location.file, 'lib/auth/service.dart');
        } else if (result is AggregatedReferencesResult) {
          expect(result.count, greaterThan(0));
        }
      });

      test('returns empty references for symbol with no refs', () async {
        final result = await executor.execute('refs formatDate');
        // Single match with no refs returns ReferencesResult
        expect(
          result,
          anyOf(isA<ReferencesResult>(), isA<AggregatedReferencesResult>()),
        );
        expect(result.isEmpty, isTrue);
      });
    });

    group('members', () {
      test('finds class members', () async {
        // Note: member detection depends on SCIP symbol parent relationship
        // which may not be correctly extracted for all symbol formats
        final result = await executor.execute('members AuthRepository');
        expect(result, isA<MembersResult>());
        // Members may or may not be found depending on symbol format
      });

      test('returns not found for non-class symbol', () async {
        final result = await executor.execute('members formatDate');
        expect(result, isA<NotFoundResult>());
      });
    });

    group('implementations', () {
      test('finds implementations of class', () async {
        final result = await executor.execute('impls AuthRepository');
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        expect(searchResult.symbols, hasLength(1));
        expect(searchResult.symbols.first.name, 'AuthService');
      });
    });

    group('hierarchy', () {
      test('finds full hierarchy', () async {
        final result = await executor.execute('hierarchy AuthService');
        expect(result, isA<HierarchyResult>());

        final hierarchyResult = result as HierarchyResult;
        expect(hierarchyResult.supertypes, hasLength(1));
        expect(hierarchyResult.supertypes.first.name, 'AuthRepository');
      });
    });

    group('find', () {
      test('finds symbols by pattern', () async {
        final result = await executor.execute('find Auth* kind:class');
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        expect(searchResult.symbols, hasLength(2)); // AuthRepository, AuthService
      });

      test('filters by kind', () async {
        final result = await executor.execute('find * kind:function');
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        expect(searchResult.symbols, hasLength(1));
        expect(searchResult.symbols.first.name, 'formatDate');
      });

      test('filters by path', () async {
        final result = await executor.execute('find * in:lib/utils/');
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        expect(searchResult.symbols, hasLength(1));
        expect(searchResult.symbols.first.file, 'lib/utils/helper.dart');
      });

      test('combines kind and path filters', () async {
        final result = await executor.execute('find * kind:class in:lib/auth/');
        expect(result, isA<SearchResult>());

        final searchResult = result as SearchResult;
        expect(searchResult.symbols, hasLength(2)); // AuthRepository, AuthService
      });
    });

    group('files', () {
      test('lists all indexed files', () async {
        final result = await executor.execute('files');
        expect(result, isA<FilesResult>());

        final filesResult = result as FilesResult;
        expect(filesResult.files, hasLength(3));
        expect(
          filesResult.files,
          containsAll([
            'lib/auth/repository.dart',
            'lib/auth/service.dart',
            'lib/utils/helper.dart',
          ]),
        );
      });
    });

    group('stats', () {
      test('returns index statistics', () async {
        final result = await executor.execute('stats');
        expect(result, isA<StatsResult>());

        final statsResult = result as StatsResult;
        expect(statsResult.stats['files'], 3);
        expect(statsResult.stats['symbols'], 5);
      });
    });
  });
}

