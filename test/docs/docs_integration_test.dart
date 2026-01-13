import 'dart:io';

import 'package:path/path.dart' as p;
// ignore: implementation_imports
import 'package:scip_dart/src/gen/scip.pb.dart' as scip;
import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

/// Integration tests for the docs infrastructure using the sample Flutter app fixture.
void main() {
  late ScipIndex index;
  late String fixturePath;

  setUpAll(() async {
    fixturePath = p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'sample_flutter_app',
    );

    index = await _buildMockIndex(fixturePath);
  });

  group('StructureHash integration', () {
    test('computes hash for fixture folders', () {
      // Get all unique folders from the index
      final folders = index.files.map((f) => p.dirname(f)).toSet();

      print('\n=== Folders in fixture ===');
      for (final folder in folders.toList()..sort()) {
        final hash = StructureHash.computeFolderHash(index, folder);
        print('$folder: ${hash.isEmpty ? "(empty)" : hash.substring(0, 8)}...');
      }

      // Auth pages folder should have a non-empty hash
      final authPagesHash = StructureHash.computeFolderHash(
        index,
        'lib/features/auth/pages',
      );
      expect(authPagesHash, isNotEmpty);
    });

    test('different folders have different hashes', () {
      final authHash = StructureHash.computeFolderHash(
        index,
        'lib/features/auth/pages',
      );
      final productsHash = StructureHash.computeFolderHash(
        index,
        'lib/features/products/pages',
      );

      expect(authHash, isNot(equals(productsHash)));
    });

    test('computes file hash', () {
      final hash = StructureHash.computeFileHash(
        index,
        'lib/features/auth/pages/login_page.dart',
      );

      expect(hash, isNotEmpty);
      print('\nLoginPage file hash: ${hash.substring(0, 8)}...');
    });
  });

  group('FolderDependencyGraph integration', () {
    test('builds graph from fixture index', () {
      final graph = FolderDependencyGraph.build(index);

      expect(graph.folders, isNotEmpty);

      print('\n=== Folder graph stats ===');
      print('Folders: ${graph.stats['folders']}');
      print('Internal edges: ${graph.stats['internalEdges']}');
      print('External packages: ${graph.stats['externalPackages']}');
    });

    test('detects folder structure', () {
      final graph = FolderDependencyGraph.build(index);

      // Should have lib folder structure
      expect(graph.folders.any((f) => f.contains('lib/features/auth')), isTrue);
      expect(graph.folders.any((f) => f.contains('lib/features/products')), isTrue);
      expect(graph.folders.any((f) => f.contains('lib/core')), isTrue);
    });

    test('can query dependencies', () {
      final graph = FolderDependencyGraph.build(index);

      print('\n=== Folder dependencies ===');
      for (final folder in graph.folders.toList()..sort()) {
        final internal = graph.getInternalDependencies(folder);
        final external = graph.getExternalDependencies(folder);

        if (internal.isNotEmpty || external.isNotEmpty) {
          print('$folder:');
          if (internal.isNotEmpty) print('  internal: $internal');
          if (external.isNotEmpty) print('  external: $external');
        }
      }
    });
  });

  group('TopologicalSort integration', () {
    test('sorts fixture folders in dependency order', () {
      final graph = FolderDependencyGraph.build(index);
      final sorted = TopologicalSort.sort(graph);

      expect(sorted, isNotEmpty);

      print('\n=== Generation order ===');
      for (var i = 0; i < sorted.length; i++) {
        final group = sorted[i];
        if (group.length == 1) {
          print('$i: ${group.first}');
        } else {
          print('$i: [CYCLE] ${group.join(", ")}');
        }
      }
    });

    test('detects cycles if any', () {
      final graph = FolderDependencyGraph.build(index);
      final hasCycles = TopologicalSort.hasCycles(graph.internalDependencyGraph);

      print('\n=== Cycle detection ===');
      print('Has cycles: $hasCycles');

      if (hasCycles) {
        final cycles = TopologicalSort.getCycles(graph.internalDependencyGraph);
        for (final cycle in cycles) {
          print('Cycle: ${cycle.join(" <-> ")}');
        }
      }
    });
  });

  group('DocManifest integration', () {
    test('creates manifest with structure hashes', () async {
      final graph = FolderDependencyGraph.build(index);
      final manifest = DocManifest();

      // Compute and store hashes for all folders
      for (final folder in graph.folders) {
        final hash = StructureHash.computeFolderHash(index, folder);
        manifest.updateFolder(
          folder,
          FolderDocState(
            structureHash: hash,
            docHash: 'not-generated-yet',
            generatedAt: DateTime.now(),
            internalDeps: graph.getInternalDependencies(folder).toList(),
            externalDeps: graph.getExternalDependencies(folder).toList(),
          ),
        );
      }

      expect(manifest.folders.length, equals(graph.folders.length));

      // All folders should be dirty (no docHash yet)
      for (final folder in graph.folders) {
        final currentHash = StructureHash.computeFolderHash(index, folder);
        // Should NOT be dirty - hash matches
        expect(manifest.isFolderDirty(folder, currentHash), isFalse);
      }
    });

    test('saves and loads manifest', () async {
      final tempDir = await Directory.systemTemp.createTemp('manifest_test');
      final manifestPath = p.join(tempDir.path, 'manifest.json');

      try {
        final graph = FolderDependencyGraph.build(index);
        final manifest = DocManifest();

        // Add some folder states
        for (final folder in graph.folders.take(3)) {
          final hash = StructureHash.computeFolderHash(index, folder);
          manifest.updateFolder(
            folder,
            FolderDocState(
              structureHash: hash,
              docHash: 'doc-$folder',
              generatedAt: DateTime.now(),
            ),
          );
        }

        // Save
        await manifest.save(manifestPath);

        // Load
        final loaded = await DocManifest.load(manifestPath);

        expect(loaded.folders.length, equals(3));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('LinkTransformer integration', () {
    test('transforms scip:// URIs in doc content', () async {
      final tempDocsDir = await Directory.systemTemp.createTemp('docs_test');

      try {
        final transformer = LinkTransformer(
          index: index,
          docsRoot: tempDocsDir.path,
          projectRoot: fixturePath,
        );

        const sourceDoc = '''
# Auth Feature

The [`LoginPage`][login] handles user authentication.

[login]: scip://lib/features/auth/pages/login_page.dart/LoginPage#
''';

        final rendered = transformer.transform(sourceDoc);

        print('\n=== Link transformation ===');
        print('Source:');
        print(sourceDoc);
        print('\nRendered:');
        print(rendered);

        // Link should be transformed (even if to #symbol-not-found in mock)
        expect(rendered, isNot(contains('scip://')));
      } finally {
        await tempDocsDir.delete(recursive: true);
      }
    });

    test('extracts scip URIs from doc', () {
      final transformer = LinkTransformer(
        index: index,
        docsRoot: '/tmp/docs',
        projectRoot: fixturePath,
      );

      const doc = '''
[auth]: scip://lib/auth/service.dart/AuthService#
[login]: scip://lib/auth/service.dart/AuthService#login().
[home]: scip://lib/pages/home.dart/HomePage#
''';

      final uris = transformer.extractScipUris(doc);

      expect(uris.length, equals(3));
      expect(uris, contains('lib/auth/service.dart/AuthService#'));
    });
  });

  group('End-to-end pipeline', () {
    test('full docs infrastructure workflow', () async {
      // 1. Build folder graph
      final graph = FolderDependencyGraph.build(index);
      expect(graph.folders, isNotEmpty);

      // 2. Get generation order
      final order = TopologicalSort.sort(graph);
      expect(order, isNotEmpty);

      // 3. Compute structure hashes
      final hashes = <String, String>{};
      for (final folder in graph.folders) {
        hashes[folder] = StructureHash.computeFolderHash(index, folder);
      }

      // 4. Create manifest
      final manifest = DocManifest();

      // 5. Check what's dirty (everything, since fresh manifest)
      final dirty = manifest.getDirtyFolders(hashes);
      expect(dirty.length, equals(graph.folders.length));

      // 6. "Generate" docs (simulate)
      for (final group in order) {
        for (final folder in group) {
          manifest.updateFolder(
            folder,
            FolderDocState(
              structureHash: hashes[folder]!,
              docHash: 'generated-${DateTime.now().millisecondsSinceEpoch}',
              generatedAt: DateTime.now(),
              internalDeps: graph.getInternalDependencies(folder).toList(),
              externalDeps: graph.getExternalDependencies(folder).toList(),
            ),
          );
        }
      }

      // 7. Now nothing should be dirty
      final stillDirty = manifest.getDirtyFolders(hashes);
      expect(stillDirty, isEmpty);

      print('\n=== Pipeline complete ===');
      print('Folders processed: ${graph.folders.length}');
      print('Generation groups: ${order.length}');
      print('Initial dirty: ${dirty.length}');
      print('Final dirty: ${stillDirty.length}');
    });
  });
}

/// Build a mock index from fixture files (same as fixture_test.dart).
Future<ScipIndex> _buildMockIndex(String fixturePath) async {
  final documents = <scip.Document>[];
  final libDir = Directory(p.join(fixturePath, 'lib'));

  if (!await libDir.exists()) {
    throw Exception('Fixture lib directory not found: ${libDir.path}');
  }

  await for (final entity in libDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      final relativePath = p.relative(entity.path, from: fixturePath);
      final content = await entity.readAsString();

      // Parse class declarations
      final classMatches = RegExp(r'class\s+(\w+)(?:\s+extends\s+(\w+))?')
          .allMatches(content);

      final symbols = <scip.SymbolInformation>[];
      final occurrences = <scip.Occurrence>[];

      for (final match in classMatches) {
        final className = match.group(1)!;
        final parentClass = match.group(2);
        final symbolId = 'scip-dart fixture 1.0.0 $relativePath/$className#';

        // Extract doc comments before the class
        final beforeClass = content.substring(0, match.start);
        final docMatch =
            RegExp(r'((?:///[^\n]*\n)+)\s*$').firstMatch(beforeClass);
        final docs = docMatch != null
            ? docMatch
                .group(1)!
                .split('\n')
                .map((l) => l.replaceFirst('/// ', ''))
                .toList()
            : <String>[];

        final relationships = <scip.Relationship>[];
        if (parentClass != null) {
          relationships.add(
            scip.Relationship(
              symbol: 'scip-dart flutter 3.0.0 $parentClass#',
              isImplementation: true,
            ),
          );
        }

        symbols.add(
          scip.SymbolInformation(
            symbol: symbolId,
            documentation: docs,
            kind: scip.SymbolInformation_Kind.Class,
            displayName: className,
            relationships: relationships,
          ),
        );

        // Find the line number for the class definition
        final lineNumber =
            '\n'.allMatches(content.substring(0, match.start)).length;

        occurrences.add(
          scip.Occurrence(
            symbol: symbolId,
            range: [
              lineNumber,
              match.start - content.lastIndexOf('\n', match.start) - 1,
            ],
            symbolRoles: scip.SymbolRole.Definition.value,
          ),
        );
      }

      documents.add(
        scip.Document(
          language: 'Dart',
          relativePath: relativePath,
          symbols: symbols,
          occurrences: occurrences,
        ),
      );
    }
  }

  final rawIndex = scip.Index(
    metadata: scip.Metadata(
      projectRoot: Uri.file(fixturePath).toString(),
    ),
    documents: documents,
  );

  return ScipIndex.fromScipIndex(rawIndex, projectRoot: fixturePath);
}
