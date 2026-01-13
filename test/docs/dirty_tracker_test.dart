import 'package:scip_server/scip_server.dart';
import 'package:test/test.dart';

import '../fixtures/mock_scip_index.dart';

void main() {
  group('DirtyTracker', () {
    group('computeDirtyState', () {
      test('marks all folders dirty when manifest is empty', () {
        final index = MockScipIndex.withDependencies();
        final graph = FolderDependencyGraph.build(index);
        final manifest = DocManifest();

        final tracker = DirtyTracker(
          index: index,
          graph: graph,
          manifest: manifest,
        );

        final state = tracker.computeDirtyState();

        // All folders should be dirty (no previous state)
        expect(state.dirtyFolders, equals(graph.folders));
      });

      test('no folders dirty when hashes match', () {
        final index = MockScipIndex.withDependencies();
        final graph = FolderDependencyGraph.build(index);

        // Pre-populate manifest with current hashes
        final manifest = DocManifest();
        for (final folder in graph.folders) {
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

        final tracker = DirtyTracker(
          index: index,
          graph: graph,
          manifest: manifest,
        );

        final state = tracker.computeDirtyState();

        // Folders should not be dirty
        expect(state.dirtyFolders, isEmpty);
        // Note: modules and project may still be dirty if not in manifest,
        // but folder-level dirty detection works correctly
      });

      test('marks folder dirty when hash changes', () {
        final index = MockScipIndex.withDependencies();
        final graph = FolderDependencyGraph.build(index);

        // Pre-populate manifest with WRONG hashes
        final manifest = DocManifest();
        for (final folder in graph.folders) {
          manifest.updateFolder(
            folder,
            FolderDocState(
              structureHash: 'old-hash',
              docHash: 'doc-$folder',
              generatedAt: DateTime.now(),
            ),
          );
        }

        final tracker = DirtyTracker(
          index: index,
          graph: graph,
          manifest: manifest,
        );

        final state = tracker.computeDirtyState();

        // All folders should be dirty (hashes don't match)
        expect(state.dirtyFolders, equals(graph.folders));
      });

      test('provides generation order', () {
        final index = MockScipIndex.withDependencies();
        final graph = FolderDependencyGraph.build(index);
        final manifest = DocManifest();

        final tracker = DirtyTracker(
          index: index,
          graph: graph,
          manifest: manifest,
        );

        final state = tracker.computeDirtyState();

        expect(state.generationOrder, isNotEmpty);

        // Flatten and check all folders are included
        final allFolders =
            state.generationOrder.expand((level) => level).toSet();
        expect(allFolders, equals(graph.folders));
      });

      test('includes structure hashes for all folders', () {
        final index = MockScipIndex.withDependencies();
        final graph = FolderDependencyGraph.build(index);
        final manifest = DocManifest();

        final tracker = DirtyTracker(
          index: index,
          graph: graph,
          manifest: manifest,
        );

        final state = tracker.computeDirtyState();

        expect(state.structureHashes.keys.toSet(), equals(graph.folders));
        for (final hash in state.structureHashes.values) {
          expect(hash, isNotEmpty);
        }
      });
    });

    group('module detection', () {
      test('auto-detects modules from folder structure', () {
        final index = MockScipIndex.withDependencies();
        final graph = FolderDependencyGraph.build(index);
        final manifest = DocManifest();

        final tracker = DirtyTracker(
          index: index,
          graph: graph,
          manifest: manifest,
        );

        final state = tracker.computeDirtyState();

        // Should detect at least one module
        expect(state.dirtyModules, isNotEmpty);
      });

      test('uses provided module definitions', () {
        final index = MockScipIndex.withDependencies();
        final graph = FolderDependencyGraph.build(index);
        final manifest = DocManifest();

        final tracker = DirtyTracker(
          index: index,
          graph: graph,
          manifest: manifest,
          moduleDefinitions: {
            'core': ['lib/core'],
            'auth': ['lib/features/auth'],
          },
        );

        final state = tracker.computeDirtyState();

        // Should have both modules dirty
        expect(state.dirtyModules, containsAll(['core', 'auth']));
      });
    });

    group('toSummary', () {
      test('provides summary stats', () {
        final index = MockScipIndex.withDependencies();
        final graph = FolderDependencyGraph.build(index);
        final manifest = DocManifest();

        final tracker = DirtyTracker(
          index: index,
          graph: graph,
          manifest: manifest,
        );

        final state = tracker.computeDirtyState();
        final summary = state.toSummary();

        expect(summary['dirtyFolders'], isA<int>());
        expect(summary['dirtyModules'], isA<int>());
        expect(summary['projectDirty'], isA<bool>());
        expect(summary['totalFolders'], isA<int>());
        expect(summary['generationLevels'], isA<int>());
      });
    });
  });

  group('DirtyTracker static methods', () {
    test('computeDocHash produces consistent hash', () {
      const content = '# Test Doc\n\nSome content.';

      final hash1 = DirtyTracker.computeDocHash(content);
      final hash2 = DirtyTracker.computeDocHash(content);

      expect(hash1, equals(hash2));
    });

    test('computeDocHash produces different hashes for different content', () {
      const content1 = '# Doc 1';
      const content2 = '# Doc 2';

      final hash1 = DirtyTracker.computeDocHash(content1);
      final hash2 = DirtyTracker.computeDocHash(content2);

      expect(hash1, isNot(equals(hash2)));
    });

    test('createFolderState creates valid state', () {
      final state = DirtyTracker.createFolderState(
        structureHash: 'abc123',
        docContent: '# My Doc',
        internalDeps: ['lib/core'],
        externalDeps: ['http'],
        smartSymbols: ['scip://lib/test#'],
      );

      expect(state.structureHash, 'abc123');
      expect(state.docHash, isNotEmpty);
      expect(state.internalDeps, contains('lib/core'));
      expect(state.externalDeps, contains('http'));
      expect(state.smartSymbols, contains('scip://lib/test#'));
    });

    test('createModuleState creates valid state', () {
      final state = DirtyTracker.createModuleState(
        docContent: '# Module Doc',
        childFolders: ['lib/a', 'lib/b'],
        folderDocHashes: {
          'lib/a': 'hash-a',
          'lib/b': 'hash-b',
        },
      );

      expect(state.docHash, isNotEmpty);
      expect(state.childFolders, hasLength(2));
      expect(state.folderDocHashes, hasLength(2));
    });

    test('createProjectState creates valid state', () {
      final state = DirtyTracker.createProjectState(
        docContent: '# Project Doc',
        moduleDocHashes: {
          'auth': 'hash-auth',
          'core': 'hash-core',
        },
      );

      expect(state.docHash, isNotEmpty);
      expect(state.moduleDocHashes, hasLength(2));
    });
  });

  group('DirtyState', () {
    test('isDirty returns true when folders dirty', () {
      const state = DirtyState(
        dirtyFolders: {'lib/a'},
        dirtyModules: {},
        projectDirty: false,
        generationOrder: [],
        structureHashes: {},
      );

      expect(state.isDirty, isTrue);
    });

    test('isDirty returns true when modules dirty', () {
      const state = DirtyState(
        dirtyFolders: {},
        dirtyModules: {'auth'},
        projectDirty: false,
        generationOrder: [],
        structureHashes: {},
      );

      expect(state.isDirty, isTrue);
    });

    test('isDirty returns true when project dirty', () {
      const state = DirtyState(
        dirtyFolders: {},
        dirtyModules: {},
        projectDirty: true,
        generationOrder: [],
        structureHashes: {},
      );

      expect(state.isDirty, isTrue);
    });

    test('isDirty returns false when nothing dirty', () {
      const state = DirtyState(
        dirtyFolders: {},
        dirtyModules: {},
        projectDirty: false,
        generationOrder: [],
        structureHashes: {},
      );

      expect(state.isDirty, isFalse);
    });
  });
}
