// Tests for IndexProvider and PackageRegistryProvider
// ignore_for_file: implementation_imports
import 'package:code_context/code_context.dart';
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:test/test.dart';

void main() {
  group('PackageRegistryProvider', () {
    late ScipIndex projectIndex;
    late ScipIndex externalIndex;
    late PackageRegistry registry;
    late PackageRegistryProvider provider;

    setUp(() {
      // Create project index
      projectIndex = ScipIndex.empty(projectRoot: '/test/project');
      projectIndex.updateDocument(
        scip.Document(
          relativePath: 'lib/main.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'dart pub test lib/main.dart/MyApp#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'MyApp',
            ),
            scip.SymbolInformation(
              symbol: 'dart pub test lib/main.dart/MyApp#run().',
              kind: scip.SymbolInformation_Kind.Method,
              displayName: 'run',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'dart pub test lib/main.dart/MyApp#',
              range: [5, 6, 5, 11],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          ],
        ),
      );

      // Create external index
      externalIndex = ScipIndex.empty(projectRoot: '/external/pkg');
      externalIndex.updateDocument(
        scip.Document(
          relativePath: 'lib/helper.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'dart pub external 1.0.0 lib/helper.dart/Helper#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'Helper',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'dart pub external 1.0.0 lib/helper.dart/Helper#',
              range: [1, 6, 1, 12],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          ],
        ),
      );

      // Create registry
      registry = PackageRegistry.forTesting(
        projectIndex: projectIndex,
        packageIndexes: {'external-1.0.0': externalIndex},
      );

      provider = PackageRegistryProvider(registry);
    });

    test('implements IndexProvider', () {
      expect(provider, isA<IndexProvider>());
    });

    test('projectIndex returns main index', () {
      expect(provider.projectIndex, same(projectIndex));
    });

    test('localIndexes returns map of local packages', () {
      final locals = provider.localIndexes;
      expect(locals, isA<Map<String, ScipIndex>>());
    });

    test('allExternalIndexes includes loaded packages', () {
      final externals = provider.allExternalIndexes.toList();
      expect(externals, contains(externalIndex));
    });

    test('allIndexes includes both local and external', () {
      final all = provider.allIndexes.toList();
      expect(all, contains(projectIndex));
      expect(all, contains(externalIndex));
    });

    test('getSymbol finds symbol in project', () {
      final symbol = provider.getSymbol('dart pub test lib/main.dart/MyApp#');
      expect(symbol, isNotNull);
      expect(symbol!.name, 'MyApp');
    });

    test('getSymbol finds symbol in external', () {
      final symbol = provider.getSymbol(
        'dart pub external 1.0.0 lib/helper.dart/Helper#',
      );
      expect(symbol, isNotNull);
      expect(symbol!.name, 'Helper');
    });

    test('getSymbol returns null for unknown', () {
      final symbol = provider.getSymbol('nonexistent');
      expect(symbol, isNull);
    });

    test('findSymbols searches across indexes', () {
      final symbols = provider.findSymbols('*');
      expect(symbols.length, greaterThan(0));
    });

    test('findQualified finds qualified symbols', () {
      final symbols = provider.findQualified('MyApp', 'run');
      expect(symbols, isNotEmpty);
      expect(symbols.first.name, 'run');
    });

    test('toProvider extension method works', () {
      final fromExtension = registry.toProvider();
      expect(fromExtension, isA<IndexProvider>());
      expect(fromExtension, isA<PackageRegistryProvider>());
    });

    test('registry getter returns underlying registry', () {
      expect(provider.registry, same(registry));
    });
  });

  group('IndexProvider with QueryExecutor', () {
    late ScipIndex projectIndex;
    late ScipIndex externalIndex;
    late PackageRegistry registry;
    late PackageRegistryProvider provider;
    late QueryExecutor executor;

    setUp(() {
      // Create project index
      projectIndex = ScipIndex.empty(projectRoot: '/test/project');
      projectIndex.updateDocument(
        scip.Document(
          relativePath: 'lib/main.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'dart pub test lib/main.dart/MyService#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'MyService',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'dart pub test lib/main.dart/MyService#',
              range: [5, 6, 5, 15],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          ],
        ),
      );

      // Create external index
      externalIndex = ScipIndex.empty(projectRoot: '/external/pkg');
      externalIndex.updateDocument(
        scip.Document(
          relativePath: 'lib/base.dart',
          language: 'Dart',
          symbols: [
            scip.SymbolInformation(
              symbol: 'dart pub external 1.0.0 lib/base.dart/BaseService#',
              kind: scip.SymbolInformation_Kind.Class,
              displayName: 'BaseService',
            ),
          ],
          occurrences: [
            scip.Occurrence(
              symbol: 'dart pub external 1.0.0 lib/base.dart/BaseService#',
              range: [1, 6, 1, 17],
              symbolRoles: scip.SymbolRole.Definition.value,
            ),
          ],
        ),
      );

      // Create registry and provider
      registry = PackageRegistry.forTesting(
        projectIndex: projectIndex,
        packageIndexes: {'external-1.0.0': externalIndex},
      );
      provider = PackageRegistryProvider(registry);

      // Create executor with provider
      executor = QueryExecutor(projectIndex, provider: provider);
    });

    test('find queries across all indexes', () async {
      final result = await executor.execute('find *Service kind:class');

      expect(result, isA<SearchResult>());
      final searchResult = result as SearchResult;

      final names = searchResult.symbols.map((s) => s.name).toList();
      expect(names, containsAll(['MyService', 'BaseService']));
    });

    test('stats includes external packages', () async {
      final result = await executor.execute('stats');

      expect(result, isA<StatsResult>());
      final statsResult = result as StatsResult;

      expect(statsResult.stats['symbols'], greaterThan(0));
    });
  });

  group('ReferenceWithSource', () {
    test('has required fields', () {
      final occurrence = OccurrenceInfo(
        symbol: 'test#',
        file: 'lib/test.dart',
        line: 10,
        column: 5,
        endLine: 10,
        endColumn: 10,
        isDefinition: false,
      );

      final ref = ReferenceWithSource(
        ref: occurrence,
        sourceRoot: '/path/to/source',
      );

      expect(ref.ref, same(occurrence));
      expect(ref.sourceRoot, '/path/to/source');
    });
  });

  group('GrepMatchInfo', () {
    test('has required fields', () {
      final match = GrepMatchInfo(
        file: 'lib/test.dart',
        line: 10,
        column: 5,
        matchText: 'TODO: fix this',
        contextLines: ['line 9', 'TODO: fix this', 'line 11'],
        contextBefore: 1,
        symbolContext: 'MyClass.myMethod',
        matchLineCount: 1,
      );

      expect(match.file, 'lib/test.dart');
      expect(match.line, 10);
      expect(match.column, 5);
      expect(match.matchText, 'TODO: fix this');
      expect(match.contextLines, hasLength(3));
      expect(match.contextBefore, 1);
      expect(match.symbolContext, 'MyClass.myMethod');
      expect(match.matchLineCount, 1);
    });

    test('defaults contextBefore to 0', () {
      final match = GrepMatchInfo(
        file: 'lib/test.dart',
        line: 10,
        column: 5,
        matchText: 'match',
      );

      expect(match.contextBefore, 0);
      expect(match.matchLineCount, 1);
    });
  });
}
