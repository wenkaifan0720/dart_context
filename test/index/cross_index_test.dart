// Tests for cross-index source operations:
// - IndexRegistry.findOwningIndex
// - IndexRegistry.findDefinition across indexes
// - IndexRegistry.getSource with sourceRoot
// - IndexRegistry.findAllReferences
// - QueryExecutor using registry for source/sig/refs/calls

// ignore_for_file: implementation_imports
import 'dart:io';

import 'package:dart_context/src/index/index_registry.dart';
import 'package:dart_context/src/index/scip_index.dart';
import 'package:dart_context/src/query/query_executor.dart';
import 'package:dart_context/src/query/query_result.dart';
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String projectRoot;
  late String externalSourceRoot;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cross_index_test');
    projectRoot = '${tempDir.path}/project';
    externalSourceRoot = '${tempDir.path}/external_pkg';

    // Create project directory
    await Directory(projectRoot).create(recursive: true);
    await Directory('$projectRoot/lib').create(recursive: true);

    // Create external package source directory
    await Directory(externalSourceRoot).create(recursive: true);
    await Directory('$externalSourceRoot/lib').create(recursive: true);

    // Create project source file
    await File('$projectRoot/lib/main.dart').writeAsString('''
import 'package:external_pkg/utils.dart';

void main() {
  final helper = ExternalHelper();
  helper.doWork();
}

class LocalClass {
  void localMethod() {}
}
''');

    // Create external package source file
    await File('$externalSourceRoot/lib/utils.dart').writeAsString('''
class ExternalHelper {
  void doWork() {
    print('working');
  }
  
  String getName() {
    return 'helper';
  }
}
''');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('ScipIndex sourceRoot', () {
    test('sourceRoot defaults to projectRoot', () {
      final index = ScipIndex.empty(projectRoot: '/test');
      expect(index.sourceRoot, '/test');
      expect(index.projectRoot, '/test');
    });

    test('sourceRoot can be different from projectRoot', () async {
      // Create an index with a different source root
      final index = ScipIndex.fromScipIndex(
        scip.Index(documents: []),
        projectRoot: '/cache/index',
        sourceRoot: '/actual/source',
      );
      expect(index.projectRoot, '/cache/index');
      expect(index.sourceRoot, '/actual/source');
    });
  });

  group('IndexRegistry findOwningIndex', () {
    late ScipIndex projectIndex;
    late ScipIndex packageIndex;
    late IndexRegistry registry;

    setUp(() {
      projectIndex = ScipIndex.empty(projectRoot: projectRoot);
      projectIndex.updateDocument(scip.Document(
        relativePath: 'lib/main.dart',
        symbols: [
          scip.SymbolInformation(
            symbol: 'project lib/main.dart/LocalClass#',
            kind: scip.SymbolInformation_Kind.Class,
            displayName: 'LocalClass',
          ),
        ],
        occurrences: [
          scip.Occurrence(
            symbol: 'project lib/main.dart/LocalClass#',
            range: [8, 6, 8, 16],
            symbolRoles: scip.SymbolRole.Definition.value,
          ),
        ],
      ));

      packageIndex = ScipIndex.fromScipIndex(
        scip.Index(documents: [
          scip.Document(
            relativePath: 'lib/utils.dart',
            symbols: [
              scip.SymbolInformation(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                kind: scip.SymbolInformation_Kind.Class,
                displayName: 'ExternalHelper',
              ),
            ],
            occurrences: [
              scip.Occurrence(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                range: [0, 6, 0, 20],
                symbolRoles: scip.SymbolRole.Definition.value,
              ),
            ],
          ),
        ]),
        projectRoot: '${tempDir.path}/cache/external_pkg',
        sourceRoot: externalSourceRoot,
      );

      registry = IndexRegistry.withIndexes(
        projectIndex: projectIndex,
        packageIndexes: {'external_pkg-1.0.0': packageIndex},
      );
    });

    test('finds project symbol in project index', () {
      final owningIndex = registry.findOwningIndex(
        'project lib/main.dart/LocalClass#',
      );
      expect(owningIndex, same(projectIndex));
    });

    test('finds external symbol in package index', () {
      final owningIndex = registry.findOwningIndex(
        'external_pkg lib/utils.dart/ExternalHelper#',
      );
      expect(owningIndex, same(packageIndex));
    });

    test('returns null for unknown symbol', () {
      final owningIndex = registry.findOwningIndex(
        'unknown lib/foo.dart/Unknown#',
      );
      expect(owningIndex, isNull);
    });
  });

  group('IndexRegistry findDefinition', () {
    late ScipIndex projectIndex;
    late ScipIndex packageIndex;
    late IndexRegistry registry;

    setUp(() {
      projectIndex = ScipIndex.empty(projectRoot: projectRoot);
      projectIndex.updateDocument(scip.Document(
        relativePath: 'lib/main.dart',
        symbols: [
          scip.SymbolInformation(
            symbol: 'project lib/main.dart/LocalClass#',
            kind: scip.SymbolInformation_Kind.Class,
          ),
        ],
        occurrences: [
          scip.Occurrence(
            symbol: 'project lib/main.dart/LocalClass#',
            range: [8, 6, 8, 16],
            symbolRoles: scip.SymbolRole.Definition.value,
          ),
        ],
      ));

      packageIndex = ScipIndex.fromScipIndex(
        scip.Index(documents: [
          scip.Document(
            relativePath: 'lib/utils.dart',
            symbols: [
              scip.SymbolInformation(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                kind: scip.SymbolInformation_Kind.Class,
              ),
            ],
            occurrences: [
              scip.Occurrence(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                range: [0, 6, 0, 20],
                symbolRoles: scip.SymbolRole.Definition.value,
              ),
            ],
          ),
        ]),
        projectRoot: '${tempDir.path}/cache/external_pkg',
        sourceRoot: externalSourceRoot,
      );

      registry = IndexRegistry.withIndexes(
        projectIndex: projectIndex,
        packageIndexes: {'external_pkg-1.0.0': packageIndex},
      );
    });

    test('finds definition in project', () {
      final def = registry.findDefinition('project lib/main.dart/LocalClass#');
      expect(def, isNotNull);
      expect(def!.file, 'lib/main.dart');
      expect(def.line, 8);
    });

    test('finds definition in external package', () {
      final def = registry.findDefinition(
        'external_pkg lib/utils.dart/ExternalHelper#',
      );
      expect(def, isNotNull);
      expect(def!.file, 'lib/utils.dart');
      expect(def.line, 0);
    });

    test('returns null for unknown symbol', () {
      final def = registry.findDefinition('unknown lib/foo.dart/Unknown#');
      expect(def, isNull);
    });
  });

  group('IndexRegistry getSource with sourceRoot', () {
    late ScipIndex packageIndex;
    late IndexRegistry registry;

    setUp(() {
      final projectIndex = ScipIndex.empty(projectRoot: projectRoot);

      packageIndex = ScipIndex.fromScipIndex(
        scip.Index(documents: [
          scip.Document(
            relativePath: 'lib/utils.dart',
            symbols: [
              scip.SymbolInformation(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                kind: scip.SymbolInformation_Kind.Class,
              ),
            ],
            occurrences: [
              scip.Occurrence(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                range: [0, 0, 9, 1],
                symbolRoles: scip.SymbolRole.Definition.value,
                enclosingRange: [0, 0, 9, 1],
              ),
            ],
          ),
        ]),
        projectRoot: '${tempDir.path}/cache/external_pkg',
        sourceRoot: externalSourceRoot,
      );

      registry = IndexRegistry.withIndexes(
        projectIndex: projectIndex,
        packageIndexes: {'external_pkg-1.0.0': packageIndex},
      );
    });

    test('getSource reads from sourceRoot not projectRoot', () async {
      final source = await registry.getSource(
        'external_pkg lib/utils.dart/ExternalHelper#',
      );

      expect(source, isNotNull);
      expect(source, contains('class ExternalHelper'));
      expect(source, contains('doWork'));
    });

    test('resolveFilePath returns correct absolute path', () {
      final path = registry.resolveFilePath(
        'external_pkg lib/utils.dart/ExternalHelper#',
      );

      expect(path, isNotNull);
      expect(path, '$externalSourceRoot/lib/utils.dart');
    });
  });

  group('IndexRegistry findAllReferences', () {
    late ScipIndex projectIndex;
    late ScipIndex packageIndex;
    late IndexRegistry registry;

    setUp(() {
      projectIndex = ScipIndex.empty(projectRoot: projectRoot);
      projectIndex.updateDocument(scip.Document(
        relativePath: 'lib/main.dart',
        symbols: [
          scip.SymbolInformation(
            symbol: 'project lib/main.dart/main().',
            kind: scip.SymbolInformation_Kind.Function,
          ),
        ],
        occurrences: [
          // Reference to ExternalHelper in project
          scip.Occurrence(
            symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
            range: [3, 16, 3, 30],
          ),
        ],
      ));

      packageIndex = ScipIndex.fromScipIndex(
        scip.Index(documents: [
          scip.Document(
            relativePath: 'lib/utils.dart',
            symbols: [
              scip.SymbolInformation(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                kind: scip.SymbolInformation_Kind.Class,
              ),
            ],
            occurrences: [
              // Definition of ExternalHelper
              scip.Occurrence(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                range: [0, 6, 0, 20],
                symbolRoles: scip.SymbolRole.Definition.value,
              ),
            ],
          ),
        ]),
        projectRoot: '${tempDir.path}/cache/external_pkg',
        sourceRoot: externalSourceRoot,
      );

      registry = IndexRegistry.withIndexes(
        projectIndex: projectIndex,
        packageIndexes: {'external_pkg-1.0.0': packageIndex},
      );
    });

    test('finds references across all indexes', () {
      final refs = registry.findAllReferences(
        'external_pkg lib/utils.dart/ExternalHelper#',
      );

      // Should find ref in project (package definition has no ReadAccess role)
      expect(refs.length, greaterThanOrEqualTo(1));
      final files = refs.map((r) => r.file).toSet();
      expect(files, contains('lib/main.dart')); // Project reference
    });
  });

  group('IndexRegistry getCalls and getCallers', () {
    late ScipIndex projectIndex;
    late IndexRegistry registry;

    setUp(() {
      projectIndex = ScipIndex.empty(projectRoot: projectRoot);
      // Note: Call graph is built during indexing, so this test just
      // verifies the registry method calls the underlying index
      registry = IndexRegistry.withIndexes(
        projectIndex: projectIndex,
      );
    });

    test('getCalls returns empty for unknown symbol', () {
      final calls = registry.getCalls('unknown#method().');
      expect(calls, isEmpty);
    });

    test('getCallers returns empty for unknown symbol', () {
      final callers = registry.getCallers('unknown#method().');
      expect(callers, isEmpty);
    });
  });

  group('QueryExecutor with registry', () {
    late ScipIndex projectIndex;
    late ScipIndex packageIndex;
    late IndexRegistry registry;
    late QueryExecutor executor;

    setUp(() {
      projectIndex = ScipIndex.empty(projectRoot: projectRoot);
      projectIndex.updateDocument(scip.Document(
        relativePath: 'lib/main.dart',
        symbols: [
          scip.SymbolInformation(
            symbol: 'project lib/main.dart/LocalClass#',
            kind: scip.SymbolInformation_Kind.Class,
            displayName: 'LocalClass',
          ),
        ],
        occurrences: [
          scip.Occurrence(
            symbol: 'project lib/main.dart/LocalClass#',
            range: [8, 0, 10, 1],
            symbolRoles: scip.SymbolRole.Definition.value,
            enclosingRange: [8, 0, 10, 1],
          ),
        ],
      ));

      packageIndex = ScipIndex.fromScipIndex(
        scip.Index(documents: [
          scip.Document(
            relativePath: 'lib/utils.dart',
            symbols: [
              scip.SymbolInformation(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                kind: scip.SymbolInformation_Kind.Class,
                displayName: 'ExternalHelper',
              ),
            ],
            occurrences: [
              scip.Occurrence(
                symbol: 'external_pkg lib/utils.dart/ExternalHelper#',
                range: [0, 0, 9, 1],
                symbolRoles: scip.SymbolRole.Definition.value,
                enclosingRange: [0, 0, 9, 1],
              ),
            ],
          ),
        ]),
        projectRoot: '${tempDir.path}/cache/external_pkg',
        sourceRoot: externalSourceRoot,
      );

      registry = IndexRegistry.withIndexes(
        projectIndex: projectIndex,
        packageIndexes: {'external_pkg-1.0.0': packageIndex},
      );

      executor = QueryExecutor(
        projectIndex,
        registry: registry,
      );
    });

    test('find locates symbols in both project and external packages', () async {
      final result = await executor.execute('find External*');

      expect(result, isA<SearchResult>());
      final searchResult = result as SearchResult;
      expect(searchResult.symbols.length, 1);
      expect(searchResult.symbols.first.name, 'ExternalHelper');
    });

    test('source returns external source using sourceRoot', () async {
      final result = await executor.execute('source ExternalHelper');

      expect(result, isA<SourceResult>());
      final sourceResult = result as SourceResult;
      expect(sourceResult.source, contains('class ExternalHelper'));
      expect(sourceResult.source, contains('doWork'));
    });
  });

  group('IndexRegistry allIndexes', () {
    test('returns project, SDK, and package indexes', () {
      final projectIndex = ScipIndex.empty(projectRoot: '/project');
      final sdkIndex = ScipIndex.empty(projectRoot: '/sdk');
      final pkg1Index = ScipIndex.empty(projectRoot: '/pkg1');
      final pkg2Index = ScipIndex.empty(projectRoot: '/pkg2');

      final registry = IndexRegistry.withIndexes(
        projectIndex: projectIndex,
        sdkIndex: sdkIndex,
        packageIndexes: {
          'pkg1-1.0.0': pkg1Index,
          'pkg2-2.0.0': pkg2Index,
        },
      );

      final allIndexes = registry.allIndexes;
      expect(allIndexes.length, 4);
      expect(allIndexes, contains(projectIndex));
      expect(allIndexes, contains(sdkIndex));
      expect(allIndexes, contains(pkg1Index));
      expect(allIndexes, contains(pkg2Index));
    });

    test('returns only project when no external indexes', () {
      final projectIndex = ScipIndex.empty(projectRoot: '/project');
      final registry = IndexRegistry.withIndexes(
        projectIndex: projectIndex,
      );

      final allIndexes = registry.allIndexes;
      expect(allIndexes.length, 1);
      expect(allIndexes.first, same(projectIndex));
    });
  });
}

